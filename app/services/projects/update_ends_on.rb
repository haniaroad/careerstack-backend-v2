# frozen_string_literal: true

module Projects
  class UpdateEndsOn
    def self.call(project:, user:, ends_on:)
      new(project: project, user: user, ends_on: ends_on).call
    end

    def initialize(project:, user:, ends_on:)
      @project = project
      @user = user
      @ends_on = ends_on
    end

    def call
      authorize!
      Projects::Lifecycle::ActionGate.assert!(project: @project, action: :update_ends_on)

      parsed = parse_ends_on!
      if parsed < Time.find_zone!("UTC").today
        raise DomainError.new("ends_on must be today or in the future", code: "validation_error")
      end

      previous = @project.ends_on
      ActiveRecord::Base.transaction do
        @project.lock!
        Projects::Lifecycle::ActionGate.assert!(project: @project.reload, action: :update_ends_on)
        @project.update!(ends_on: parsed)

        if previous != parsed
          notify_participants!(previous: previous, next_date: parsed)
        end
      end

      Projects::Lifecycle::Evaluate.call(project: @project.reload)
      @project.reload
    end

    private

    def authorize!
      unless @project.creator_id == @user.id
        raise DomainError.new("Only the creator can update the end date", code: "forbidden", status: :forbidden)
      end
      unless @user.member_of_workspace?(@project.workspace)
        raise DomainError.new("Not a member of this workspace", code: "forbidden", status: :forbidden)
      end
      unless @project.active?
        raise DomainError.new("Only active projects can update ends_on this way", code: "validation_error")
      end
    end

    def parse_ends_on!
      raise DomainError.new("ends_on is required", code: "validation_error") if @ends_on.blank?

      Date.parse(@ends_on.to_s)
    rescue ArgumentError
      raise DomainError.new("ends_on must be a valid date", code: "validation_error")
    end

    def notify_participants!(previous:, next_date:)
      recipient_ids = ([ @project.creator_id ] + @project.memberships.active.pluck(:user_id)).uniq
      key_base = "lifecycle:ends_on_updated:#{@project.id}:#{next_date}"

      recipient_ids.each do |user_id|
        InboxAlert.find_or_create_by!(idempotency_key: "#{key_base}:user:#{user_id}") do |alert|
          alert.workspace = @project.workspace
          alert.recipient_user_id = user_id
          alert.audience = InboxAlert::AUDIENCE_USER
          alert.kind = InboxAlert::KIND_LIFECYCLE
          alert.subject_type = "Project"
          alert.subject_id = @project.id
          alert.project = @project
          alert.title = "Project end date updated"
          alert.body = "#{@project.title} end date changed from #{previous || "unset"} to #{next_date}."
          alert.urgency = InboxAlert::URGENCY_MEDIUM
          alert.organization_id = @project.workspace.organization_id
        end
      end

      recipients = User.where(id: recipient_ids)
      Notifications::Hook.emit(
        event_key: "date_changed",
        actor: @user,
        recipients: recipients,
        source: Notifications::Hook.named_source("date-changed:#{@project.id}:#{next_date}"),
        project: @project,
        payload: Notifications::Hook.project_payload(@project, "ends_on" => next_date.to_s)
      )
    end
  end
end
