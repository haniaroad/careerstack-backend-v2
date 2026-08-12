# frozen_string_literal: true

module Profiles
  # Append-only contribution activity. Idempotent via idempotency_key.
  class RecordContribution
    def self.call(user:, kind:, subject:, occurred_at: Time.current, project: nil)
      new(user: user, kind: kind, subject: subject, occurred_at: occurred_at, project: project).call
    end

    def initialize(user:, kind:, subject:, occurred_at:, project:)
      @user = user
      @kind = kind
      @subject = subject
      @occurred_at = occurred_at
      @project = project || infer_project(subject)
    end

    def call
      return nil if @user.nil? || @subject.nil?

      workspace = @project&.workspace
      workspace_kind = workspace&.organization_id.present? ? ContributionEvent::WORKSPACE_ORGANIZATION : ContributionEvent::WORKSPACE_PERSONAL
      private_org = workspace_kind == ContributionEvent::WORKSPACE_ORGANIZATION
      key = "#{@kind}:#{@subject.class.name}:#{@subject.id}"

      ContributionEvent.find_or_create_by!(idempotency_key: key) do |event|
        event.user = @user
        event.kind = @kind
        event.occurred_at = @occurred_at
        event.subject_type = @subject.class.name
        event.subject_id = @subject.id
        event.workspace_kind = workspace_kind
        event.private_org = private_org
      end
    rescue ActiveRecord::RecordNotUnique
      ContributionEvent.find_by!(idempotency_key: key)
    end

    private

    def infer_project(subject)
      case subject
      when Project then subject
      when Task then subject.project
      when TaskSubmission then subject.task.project
      else nil
      end
    end
  end
end
