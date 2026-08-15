# frozen_string_literal: true

module Projects
  module Lifecycle
    class Evaluate
      def self.call(project:)
        new(project: project).call
      end

      def initialize(project:)
        @project = project
      end

      def call
        ActiveRecord::Base.transaction do
          @project.lock!
          return @project unless @project.active?

          if @project.past_final_expiration?
            expire!
          elsif completion_criteria_met?
            complete!
          elsif newly_in_grace?
            enter_grace!
          elsif @project.ending_soon?
            notify_ending_soon!
          end

          @project.reload
        end
      end

      private

      def completion_criteria_met?
        tasks = @project.tasks.to_a
        return false if tasks.empty?

        tasks.all? { |task| task.assignee_id.present? && task.approved? }
      end

      def newly_in_grace?
        return false if @project.ends_on.blank?

        Time.find_zone!("UTC").today > @project.ends_on
      end

      def expire!
        @project.tasks.where.not(status: Task::STATUS_APPROVED).find_each do |task|
          task.update!(status: Task::STATUS_INCOMPLETE)
        end

        @project.update!(
          status: Project::STATUS_EXPIRED,
          expired_at: Time.current
        )

        expire_pending_recruitment!
        notify_audience!(
          key: "lifecycle:expired:#{@project.id}",
          title: "Project expired",
          body: "#{@project.title} has reached final expiration. Unresolved tasks were marked incomplete.",
          urgency: InboxAlert::URGENCY_HIGH
        )
      end

      def complete!
        @project.update!(
          status: Project::STATUS_COMPLETED,
          completed_at: Time.current
        )

        expire_pending_recruitment!
        @project.memberships.active.find_each do |membership|
          Profiles::RecordContribution.call(
            user: membership.user,
            kind: ContributionEvent::KIND_PROJECT_COMPLETED,
            subject: @project,
            occurred_at: @project.completed_at,
            project: @project
          )
        end
        notify_audience!(
          key: "lifecycle:completed:#{@project.id}",
          title: "Project completed",
          body: "#{@project.title} is complete — all tasks were approved.",
          urgency: InboxAlert::URGENCY_MEDIUM
        )
      end

      def enter_grace!
        expire_pending_recruitment!
        notify_audience!(
          key: "lifecycle:grace:#{@project.id}",
          title: "Project in grace period",
          body: "#{@project.title} has passed its end date. Finish outstanding work before final expiration.",
          urgency: InboxAlert::URGENCY_HIGH
        )
      end

      def notify_ending_soon!
        notify_audience!(
          key: "lifecycle:ending_soon:#{@project.id}",
          title: "Project ending soon",
          body: "#{@project.title} ends on #{@project.ends_on}. Wrap up remaining work.",
          urgency: InboxAlert::URGENCY_MEDIUM
        )
      end

      def expire_pending_recruitment!
        @project.applications.pending.find_each do |app|
          app.update!(status: ProjectApplication::STATUS_EXPIRED)
        end
        @project.invitations.pending.find_each do |invite|
          invite.update!(status: ProjectInvitation::STATUS_EXPIRED, responded_at: Time.current)
        end
      end

      def notify_audience!(key:, title:, body:, urgency:)
        recipient_ids = ([ @project.creator_id ] + @project.memberships.active.pluck(:user_id)).uniq

        recipient_ids.each do |user_id|
          InboxAlert.find_or_create_by!(idempotency_key: "#{key}:user:#{user_id}") do |alert|
            alert.workspace = @project.workspace
            alert.recipient_user_id = user_id
            alert.audience = InboxAlert::AUDIENCE_USER
            alert.kind = InboxAlert::KIND_LIFECYCLE
            alert.subject_type = "Project"
            alert.subject_id = @project.id
            alert.project = @project
            alert.title = title
            alert.body = body
            alert.urgency = urgency
            alert.organization_id = @project.workspace.organization_id
          end
        end

        event_key = lifecycle_event_key(key)
        return if event_key.nil?

        Notifications::Hook.emit(
          event_key: event_key,
          actor: nil,
          recipients: User.where(id: recipient_ids),
          source: Notifications::Hook.named_source(key),
          project: @project,
          payload: Notifications::Hook.project_payload(@project, "ends_on" => @project.ends_on.to_s)
        )
      end

      def lifecycle_event_key(key)
        return "project_completed" if key.start_with?("lifecycle:completed:")
        return "grace_period_started" if key.start_with?("lifecycle:grace:")
        return "project_ending_soon" if key.start_with?("lifecycle:ending_soon:")

        nil
      end
    end
  end
end
