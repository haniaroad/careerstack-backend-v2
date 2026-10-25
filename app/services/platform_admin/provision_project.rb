# frozen_string_literal: true

module PlatformAdmin
  # Staff create, edit, and duplicate organization projects without charging
  # credits. A team creator may already own other team projects. A participant
  # may still be on only one active project.
  class ProvisionProject
    BLOCKED = "This person is already on an active project. They can be added after that project is finished."

    def self.list(organization:)
      workspace = organization.workspace
      return [] if workspace.nil?

      Project.where(workspace_id: workspace.id).order(updated_at: :desc).includes(:creator).map { |project| summary(project) }
    end

    def self.show(project)
      detail(project)
    end

    def self.create!(actor:, organization:, params:, reason:)
      new(actor:, organization:, project: nil, params:, reason:).create!
    end

    def self.update!(actor:, project:, params:, reason:)
      new(actor:, organization: project.workspace.organization, project:, params:, reason:).update!
    end

    def self.duplicate!(actor:, project:, params:, reason:)
      new(actor:, organization: project.workspace.organization, project:, params:, reason:).duplicate!
    end

    def self.add_member!(actor:, project:, user_id:, participant_role:, reason:)
      new(actor:, organization: project.workspace.organization, project:, params: {}, reason:).add_member!(user_id, participant_role)
    end

    def self.remove_member!(actor:, project:, user_id:, reason:)
      new(actor:, organization: project.workspace.organization, project:, params: {}, reason:).remove_member!(user_id)
    end

    def initialize(actor:, organization:, project:, params:, reason:)
      @actor = actor
      @organization = organization
      @project = project
      @params = params.to_h.with_indifferent_access
      @reason = reason.to_s.strip
    end

    def create!
      require_reason!
      require_organization!
      creator = designated_creator!
      program = resolve_program!
      mode = @params[:mode].presence || Project::MODE_TEAM
      balance = credit_balance

      project = ActiveRecord::Base.transaction do
        built = build_project!(creator:, program:, mode:)
        built.memberships.create!(
          user: creator,
          role: ProjectMembership::ROLE_CREATOR,
          status: ProjectMembership::STATUS_ACTIVE
        )
        Array(@params[:members]).each do |member|
          raw = member.to_h.with_indifferent_access
          add_member_record!(built, raw[:user_id], raw[:participant_role])
        end
        create_tasks!(built, creator)
        built
      end

      assert_uncharged!(balance)
      Audit.record!(actor: @actor, action: "provision_project", target: project, reason: @reason)
      detail(project.reload)
    end

    def update!
      require_reason!
      require_project!
      balance = credit_balance
      ActiveRecord::Base.transaction do
        @project.lock!
        attrs = {}
        attrs[:title] = @params[:title].to_s.strip if @params.key?(:title)
        attrs[:summary] = @params[:summary].presence if @params.key?(:summary)
        attrs[:ends_on] = parse_date!(@params[:ends_on], "End date") if @params.key?(:ends_on)
        attrs[:visibility] = visibility! if @params.key?(:visibility)
        if @project.team?
          attrs[:joining_mode] = joining_mode! if @params.key?(:joining_mode)
          attrs[:capacity] = capacity! if @params.key?(:capacity)
          attrs[:roles_needed] = roles!(@project.roles_needed) if @params.key?(:roles_needed)
        end
        attrs[:skills] = Projects::TaxonomySelection.validate_skills!(@params[:skills], existing: @project.skills) if @params.key?(:skills)
        @project.update!(attrs) if attrs.any?
        if @project.team? && @project.capacity.to_i < @project.active_participant_count
          raise DomainError.new("Capacity cannot be lower than the current number of participants", code: "validation_error")
        end
        sync_tasks! if @params.key?(:tasks)
      end
      assert_uncharged!(balance)
      Audit.record!(actor: @actor, action: "update_project", target: @project, reason: @reason)
      detail(@project.reload)
    end

    def duplicate!
      require_reason!
      require_project!
      creator = designated_creator!
      balance = credit_balance
      source = @project
      copy = ActiveRecord::Base.transaction do
        built = source.dup
        built.assign_attributes(
          slug: nil,
          creator: creator,
          status: Project::STATUS_ACTIVE,
          staff_provisioned: true,
          confirmed_at: Time.current,
          cancelled_at: nil,
          completed_at: nil,
          expired_at: nil,
          title: @params[:title].presence || source.title
        )
        built.save!
        built.memberships.create!(
          user: creator,
          role: ProjectMembership::ROLE_CREATOR,
          status: ProjectMembership::STATUS_ACTIVE
        )
        source.tasks.order(:position).each do |task|
          built.tasks.create!(
            title: task.title,
            acceptance_criteria: task.acceptance_criteria,
            submission_expectations: task.submission_expectations,
            due_on: task.due_on,
            reference_video_url: task.reference_video_url,
            status: Task::STATUS_PENDING,
            position: task.position,
            assignee: nil
          )
        end
        built
      end
      assert_uncharged!(balance)
      Audit.record!(actor: @actor, action: "duplicate_project", target: copy, reason: @reason)
      detail(copy.reload)
    end

    def add_member!(user_id, participant_role)
      require_reason!
      require_project!
      balance = credit_balance
      ActiveRecord::Base.transaction do
        @project.lock!
        add_member_record!(@project, user_id, participant_role)
      end
      assert_uncharged!(balance)
      user = User.find(user_id)
      Audit.record!(actor: @actor, action: "add_project_member", target: user, reason: @reason)
      detail(@project.reload)
    end

    def remove_member!(user_id)
      require_reason!
      require_project!
      user = User.find(user_id)
      balance = credit_balance
      ActiveRecord::Base.transaction do
        @project.lock!
        membership = @project.memberships.active.find_by(user_id: user.id)
        raise DomainError.new("That person is not on this project", code: "validation_error") if membership.nil?
        raise DomainError.new("The project creator stays on the project", code: "validation_error") if membership.creator?

        membership.update!(status: ProjectMembership::STATUS_REMOVED)
        ProjectMembershipEvent.create!(
          project_membership: membership,
          project: @project,
          user: user,
          actor_user: @actor,
          event_type: ProjectMembershipEvent::EVENT_REMOVED,
          reason_category: "removed_by_organization",
          reason_detail: @reason
        )
        Tasks::UnassignMember.call(project: @project, user: user)
      end
      Notifications::Hook.emit(
        event_key: "removed_from_project",
        actor: @actor,
        recipients: [ user ],
        source: @project,
        project: @project,
        payload: Notifications::Hook.project_payload(@project)
      )
      assert_uncharged!(balance)
      Audit.record!(actor: @actor, action: "remove_project_member", target: user, reason: @reason)
      detail(@project.reload)
    end

    def self.summary(project)
      {
        id: project.id,
        title: project.title,
        status: project.status,
        mode: project.mode,
        ends_on: project.ends_on,
        staff_provisioned: project.staff_provisioned,
        creator_id: project.creator_id,
        creator_email: project.creator.email
      }
    end

    def self.detail(project)
      summary(project).merge(
        summary_text: project.summary,
        visibility: project.visibility,
        joining_mode: project.joining_mode,
        capacity: project.capacity,
        roles_needed: project.roles_needed,
        skills: project.skills,
        program_id: project.program_id,
        members: project.memberships.active.includes(user: :profile).map { |membership|
          {
            user_id: membership.user_id,
            email: membership.user.email,
            display_name: membership.user.profile&.display_name,
            role: membership.role,
            participant_role: membership.participant_role
          }
        },
        tasks: project.tasks.order(:position).map { |task|
          {
            id: task.id,
            title: task.title,
            acceptance_criteria: task.acceptance_criteria,
            due_on: task.due_on,
            status: task.status,
            assignee_id: task.assignee_id
          }
        }
      )
    end

    private

    def solo_mode?
      (@params[:mode].presence || @project&.mode || Project::MODE_TEAM) == Project::MODE_SOLO
    end

    def require_reason!
      raise DomainError.new("A reason is required", code: "validation_error") if @reason.blank?
    end

    def require_organization!
      raise DomainError.new("Organization was not found", code: "not_found", status: :not_found) if @organization.nil?
      Organizations::Access.require_writable!(@organization)
    end

    def require_project!
      raise DomainError.new("Project was not found", code: "not_found", status: :not_found) if @project.nil?
      raise DomainError.new("Staff can manage organization projects only", code: "validation_error") if @organization.nil?
      Organizations::Access.require_writable!(@organization)
    end

    def designated_creator!
      require_organization!
      creator = User.find_by(id: @params[:creator_id])
      unless creator
        raise DomainError.new("Choose an organization admin or manager as the creator", code: "validation_error")
      end
      membership = @organization.organization_memberships.active.find_by(user_id: creator.id)
      unless membership&.staff? && creator.adult? && !creator.pending_onboarding?
        raise DomainError.new(
          "The creator must be an onboarded admin or manager in this organization",
          code: "validation_error"
        )
      end
      if solo_mode? && ProjectMembership.active_participation?(creator)
        raise DomainError.new(BLOCKED, code: "active_participation_conflict")
      end
      creator
    end

    def resolve_program!
      if @params[:program_id].present?
        program = @organization.programs.find_by(id: @params[:program_id])
        unless program&.active?
          raise DomainError.new("Choose an active program in this organization", code: "validation_error")
        end
        return program
      end

      active = @organization.programs.active.order(:name).to_a
      name = @params[:program_name].to_s.strip
      return @organization.programs.create!(name: name, status: Program::STATUS_ACTIVE) if name.present?
      return active.first if active.one?

      if active.none?
        raise DomainError.new("Name an active program for this organization", code: "validation_error")
      end

      raise DomainError.new("Choose which program this project belongs to", code: "validation_error")
    end

    def build_project!(creator:, program:, mode:)
      ends_on = parse_date!(@params[:ends_on], "End date")
      if ends_on < Time.find_zone!("UTC").today
        raise DomainError.new("End date must be today or in the future", code: "validation_error")
      end
      team = mode == Project::MODE_TEAM
      if Array(@params[:members]).any? && !team
        raise DomainError.new(
          "A solo project has no extra members. Use a team project with capacity 1 for a single student.",
          code: "validation_error"
        )
      end

      Project.create!(
        workspace: @organization.workspace,
        creator: creator,
        program: program,
        title: @params[:title].to_s.strip,
        summary: @params[:summary].presence,
        skills: Projects::TaxonomySelection.validate_skills!(@params[:skills]),
        mode: mode,
        status: Project::STATUS_ACTIVE,
        confirmed_at: Time.current,
        staff_provisioned: true,
        source: Project::SOURCE_MANUAL,
        ends_on: ends_on,
        visibility: @params[:visibility].presence || Project::VISIBILITY_PRIVATE,
        joining_mode: team ? joining_mode! : nil,
        capacity: team ? capacity! : nil,
        roles_needed: team ? roles! : [],
        proposed_tasks: proposed_tasks
      )
    end

    def create_tasks!(project, creator)
      Array(@params[:tasks]).each_with_index do |raw, index|
        task = raw.to_h.with_indifferent_access
        assignee = assignee_for_new_task(project, creator, task[:assignee_id])
        project.tasks.create!(
          title: task[:title].presence || "Task #{index + 1}",
          acceptance_criteria: task[:acceptance_criteria].presence,
          due_on: task[:due_on].present? ? parse_date!(task[:due_on], "Task due date") : nil,
          status: Task::STATUS_PENDING,
          position: index,
          assignee: assignee
        )
      end
    end

    def assignee_for_new_task(project, creator, assignee_id)
      return creator if project.solo?
      return nil if assignee_id.blank?

      member = project.memberships.active.find_by(user_id: assignee_id)
      unless member
        raise DomainError.new("Assign tasks only to people on the project", code: "validation_error")
      end
      member.user
    end

    def add_member_record!(project, user_id, participant_role)
      raise DomainError.new("Only team projects have additional members", code: "validation_error") unless project.team?

      user = User.find_by(id: user_id)
      raise DomainError.new("Choose a person who already belongs to the organization", code: "validation_error") if user.nil?
      unless @organization.organization_memberships.active.exists?(user_id: user.id)
        raise DomainError.new("Members must already belong to the organization", code: "validation_error")
      end
      raise DomainError.new("The creator is already on the project", code: "validation_error") if user.id == project.creator_id
      if ProjectMembership.active_participation?(user)
        raise DomainError.new(BLOCKED, code: "active_participation_conflict")
      end
      if project.seats_remaining <= 0
        raise DomainError.new("Project is at capacity", code: "capacity_full", status: :conflict)
      end

      role = participant_role.to_s.strip
      unless project.roles_needed.include?(role)
        raise DomainError.new("Choose a role this project is asking for", code: "validation_error")
      end

      membership = project.memberships.create!(
        user: user,
        role: ProjectMembership::ROLE_PARTICIPANT,
        status: ProjectMembership::STATUS_ACTIVE,
        participant_role: role,
        join_source: ProjectMembership::JOIN_SOURCE_ASSIGN
      )
      ProjectMembershipEvent.create!(
        project_membership: membership,
        project: project,
        user: user,
        actor_user: @actor,
        event_type: ProjectMembershipEvent::EVENT_JOINED,
        join_source: ProjectMembership::JOIN_SOURCE_ASSIGN,
        participant_role: role
      )
      membership
    end

    def sync_tasks!
      Array(@params[:tasks]).each_with_index do |raw, index|
        task_params = raw.to_h.with_indifferent_access
        if task_params[:id].present?
          task = @project.tasks.find(task_params[:id])
          rewrite_locked!(task, task_params)
          next if task.submitted? || task.approved? || task.incomplete?

          task.update!(
            title: task_params[:title].presence || task.title,
            acceptance_criteria: task_params.key?(:acceptance_criteria) ? task_params[:acceptance_criteria].presence : task.acceptance_criteria,
            due_on: task_params.key?(:due_on) ? (task_params[:due_on].present? ? parse_date!(task_params[:due_on], "Task due date") : nil) : task.due_on,
            assignee: assignee_for_existing!(task, task_params)
          )
        else
          @project.tasks.create!(
            title: task_params[:title].presence || "Task #{index + 1}",
            acceptance_criteria: task_params[:acceptance_criteria].presence,
            due_on: task_params[:due_on].present? ? parse_date!(task_params[:due_on], "Task due date") : nil,
            status: Task::STATUS_PENDING,
            position: @project.tasks.maximum(:position).to_i + 1,
            assignee: assignee_for_new_task(@project, @project.creator, task_params[:assignee_id])
          )
        end
      end
    end

    def rewrite_locked!(task, task_params)
      return unless task.submitted? || task.approved? || task.incomplete?

      changed = task_params[:title].present? && task_params[:title] != task.title
      changed ||= task_params.key?(:acceptance_criteria) && task_params[:acceptance_criteria].presence != task.acceptance_criteria
      changed ||= task_params.key?(:assignee_id) && task_params[:assignee_id].presence != task.assignee_id
      return unless changed

      raise DomainError.new("Submitted or approved work cannot be rewritten", code: "validation_error")
    end

    def assignee_for_existing!(task, task_params)
      return task.assignee unless task_params.key?(:assignee_id)
      return nil if task_params[:assignee_id].blank?

      assignee_for_new_task(@project, @project.creator, task_params[:assignee_id])
    end

    def joining_mode!
      mode = @params[:joining_mode].presence || Project::JOINING_INVITE_ONLY
      unless Project::JOINING_MODES.include?(mode)
        raise DomainError.new("Joining mode must be application, instant, or invite only", code: "validation_error")
      end
      mode
    end

    def capacity!
      value = @params[:capacity].presence || 1
      number = Integer(value)
      unless number.between?(1, 5)
        raise DomainError.new("Capacity must be between 1 and 5", code: "validation_error")
      end
      number
    rescue ArgumentError
      raise DomainError.new("Capacity must be between 1 and 5", code: "validation_error")
    end

    def roles!(existing = [])
      Projects::TaxonomySelection.validate_roles!(@params[:roles_needed], existing: existing)
    end

    def visibility!
      value = @params[:visibility].presence || Project::VISIBILITY_PRIVATE
      unless Project::VISIBILITIES.include?(value)
        raise DomainError.new("Visibility must be public or private", code: "validation_error")
      end
      value
    end

    def proposed_tasks
      Array(@params[:tasks]).map do |raw|
        task = raw.to_h.with_indifferent_access
        { "title" => task[:title].to_s, "summary" => task[:acceptance_criteria].to_s, "recommended_due_date" => task[:due_on].to_s }
      end
    end

    def parse_date!(value, label)
      raise DomainError.new("#{label} is required", code: "validation_error") if value.blank?

      Date.iso8601(value.to_s)
    rescue Date::Error
      raise DomainError.new("#{label} must be YYYY-MM-DD", code: "validation_error")
    end

    def credit_balance
      Credits::Balance.remaining(owner: @organization)
    end

    def assert_uncharged!(before)
      return if Credits::Balance.remaining(owner: @organization) == before

      raise DomainError.new("Staff project setup must not charge organization credits", code: "validation_error")
    end

    def detail(project)
      self.class.detail(project)
    end
  end
end
