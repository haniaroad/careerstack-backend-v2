# frozen_string_literal: true

module Projects
  class CreateDraft
    def self.call(user:, workspace:, title:, summary: nil, skills: [], mode: Project::MODE_SOLO,
                  joining_mode: nil, capacity: nil, roles_needed: [], visibility: nil, program_id: nil)
      new(
        user: user,
        workspace: workspace,
        title: title,
        summary: summary,
        skills: skills,
        mode: mode,
        joining_mode: joining_mode,
        capacity: capacity,
        roles_needed: roles_needed,
        visibility: visibility,
        program_id: program_id
      ).call
    end

    def initialize(user:, workspace:, title:, summary:, skills:, mode:, joining_mode:, capacity:, roles_needed:, visibility:, program_id:)
      @user = user
      @workspace = workspace
      @title = title
      @summary = summary
      @skills = Array(skills).map { |s| s.to_s.strip }.reject(&:blank?).uniq
      @mode = mode.to_s.presence || Project::MODE_SOLO
      @joining_mode = joining_mode.presence
      @capacity = capacity
      @roles_needed = Array(roles_needed).map { |s| s.to_s.strip }.reject(&:blank?).uniq
      @visibility = visibility
      @program_id = program_id
    end

    def call
      authorize!
      validate_mode!
      validate_visibility!
      program = resolve_program

      Project.create!(
        workspace: @workspace,
        creator: @user,
        title: @title.to_s.strip,
        summary: @summary.presence,
        skills: @skills,
        mode: @mode,
        joining_mode: @mode == Project::MODE_TEAM ? @joining_mode : nil,
        capacity: @mode == Project::MODE_TEAM ? @capacity.to_i : nil,
        roles_needed: @mode == Project::MODE_TEAM ? @roles_needed : [],
        visibility: resolved_visibility,
        status: Project::STATUS_DRAFT,
        program: program
      )
    end

    private

    def authorize!
      raise DomainError.new("No active workspace", code: "no_workspace") if @workspace.nil?
      raise DomainError.new("Not a member of this workspace", code: "forbidden", status: :forbidden) unless @user.member_of_workspace?(@workspace)
      raise DomainError.new("Complete onboarding before creating projects", code: "onboarding_required", status: :forbidden) if @user.pending_onboarding?

      if @workspace.personal? && !@user.adult?
        raise DomainError.new("Personal projects require a verified adult account", code: "forbidden", status: :forbidden)
      end

      if @workspace.organization?
        Organizations::Access.require_writable!(@workspace.organization)
      end
    end

    def validate_mode!
      unless Project::MODES.include?(@mode)
        raise DomainError.new("Invalid project mode", code: "validation_error")
      end

      return unless @mode == Project::MODE_TEAM

      unless Project::JOINING_MODES.include?(@joining_mode.to_s)
        raise DomainError.new("Joining mode is required for team projects", code: "validation_error")
      end

      cap = @capacity.to_i
      unless cap.between?(1, 5)
        raise DomainError.new("Capacity must be between 1 and 5", code: "validation_error")
      end

      if @roles_needed.empty?
        raise DomainError.new("At least one role is required for team projects", code: "validation_error")
      end
    end

    def validate_visibility!
      return if @visibility.nil?

      unless Project::VISIBILITIES.include?(@visibility.to_s)
        raise DomainError.new("Invalid project visibility", code: "validation_error")
      end
    end

    def resolved_visibility
      return @visibility.to_s if @visibility.present?

      @workspace.organization? ? Project::VISIBILITY_PRIVATE : Project::VISIBILITY_PUBLIC
    end

    def resolve_program
      return nil if @workspace.personal?

      program_id = @program_id.presence || @user.membership_for(@workspace.organization)&.program_filter_program_id
      raise DomainError.new("program_id is required for organization projects", code: "validation_error") if program_id.blank?

      program = @workspace.organization.programs.find(program_id)
      raise DomainError.new("Archived programs cannot receive new projects", code: "validation_error") if program.archived?
      raise DomainError.new("Draft programs cannot receive new projects", code: "validation_error") if program.draft?

      program
    end
  end
end
