# frozen_string_literal: true

require "digest"

module Tasks
  class Submit
    def self.call(task:, user:, body: nil, links: [], signed_blob_ids: [], enqueue_review: true)
      new(
        task: task,
        user: user,
        body: body,
        links: links,
        signed_blob_ids: signed_blob_ids,
        enqueue_review: enqueue_review
      ).call
    end

    def initialize(task:, user:, body:, links:, signed_blob_ids:, enqueue_review:)
      @task = task
      @user = user
      @body = body.to_s.strip.presence
      @links = Array(links).map { |u| u.to_s.strip }.reject(&:blank?)
      @signed_blob_ids = Array(signed_blob_ids).map(&:to_s).reject(&:blank?)
      @enqueue_review = enqueue_review
    end

    def call
      authorize!
      Projects::Lifecycle::ActionGate.assert!(project: @task.project, action: :submit)
      validate_state!
      blobs = resolve_blobs!
      EvidenceLimits.validate_files!(blobs)
      validate_links!
      validate_presence!(blobs)

      submission = nil
      ActiveRecord::Base.transaction do
        @task.lock!
        Projects::Lifecycle::ActionGate.assert!(project: @task.project.reload, action: :submit)
        validate_state!

        attempt = @task.submissions.maximum(:attempt_number).to_i + 1
        fingerprint = compute_fingerprint(blobs)

        submission = TaskSubmission.new(
          task: @task,
          submitted_by: @user,
          attempt_number: attempt,
          body: @body,
          content_fingerprint: fingerprint,
          submitted_at: Time.current
        )

        @links.each { |url| submission.links.build(url: url) }
        submission.files.attach(blobs) if blobs.any?
        submission.save!

        attrs = { status: Task::STATUS_SUBMITTED }
        if @task.first_submitted_at.nil?
          attrs[:first_submitted_at] = submission.submitted_at
          attrs[:on_time] = on_time?(submission.submitted_at)
        end
        @task.update!(attrs)
      end

      review = nil
      if @enqueue_review && @task.project.solo?
        review = Ai::CreateTaskReview.call(
          task: @task.reload,
          submission: submission,
          user: @user,
          auto: true
        )
      end

      Profiles::RecordContribution.call(
        user: @user,
        kind: ContributionEvent::KIND_TASK_SUBMITTED,
        subject: submission,
        occurred_at: submission.submitted_at,
        project: @task.project
      )
      if submission.files.attached? || submission.links.any?
        Profiles::RecordContribution.call(
          user: @user,
          kind: ContributionEvent::KIND_ARTIFACT_UPLOADED,
          subject: submission,
          occurred_at: submission.submitted_at,
          project: @task.project
        )
      end

      { submission: submission.reload, review: review, task: @task.reload }.tap do |result|
        Notifications::Hook.emit(
          event_key: "submission_received",
          actor: @user,
          recipients: [ @task.project.creator ],
          source: result[:submission],
          project: @task.project,
          payload: Notifications::Hook.task_payload(@task)
        )
      end
    end

    private

    def authorize!
      raise DomainError.new("Only the assignee can submit this task", code: "forbidden", status: :forbidden) unless @task.assignee_id == @user.id
      raise DomainError.new("Not a member of this workspace", code: "forbidden", status: :forbidden) unless @user.member_of_workspace?(@task.project.workspace)
      membership = @task.project.memberships.active.find_by(user_id: @user.id)
      raise DomainError.new("Not a project participant", code: "forbidden", status: :forbidden) if membership.nil?
      @task.project.ensure_lifecycle_current!
    end

    def validate_state!
      if @task.approved?
        raise DomainError.new("Approved tasks cannot be reopened", code: "validation_error")
      end
      return if @task.submittable?

      raise DomainError.new("Task cannot be submitted in its current status", code: "validation_error")
    end

    def resolve_blobs!
      @signed_blob_ids.map do |signed_id|
        ActiveStorage::Blob.find_signed!(signed_id)
      rescue ActiveSupport::MessageVerifier::InvalidSignature, ActiveRecord::RecordNotFound
        raise DomainError.new("Invalid file upload reference", code: "validation_error")
      end
    end

    def validate_links!
      @links.each do |url|
        uri = URI.parse(url)
        unless uri.is_a?(URI::HTTPS) && uri.host.present?
          raise DomainError.new("Artifact links must be valid https:// URLs", code: "validation_error")
        end
      rescue URI::InvalidURIError
        raise DomainError.new("Artifact links must be valid https:// URLs", code: "validation_error")
      end
    end

    def validate_presence!(blobs)
      return if @body.present? || @links.any? || blobs.any?

      raise DomainError.new("Submission requires text and/or evidence", code: "validation_error")
    end

    def compute_fingerprint(blobs)
      parts = [
        @body.to_s,
        @links.sort.join("\n"),
        blobs.map { |b| "#{b.checksum}:#{b.byte_size}:#{b.filename}" }.sort.join("|")
      ]
      Digest::SHA256.hexdigest(parts.join("||"))
    end

    def on_time?(submitted_at)
      return true if @task.due_on.blank?

      submitted_at.to_date <= @task.due_on
    end
  end
end
