# frozen_string_literal: true

module PlatformAdmin
  class Operations
    def self.require_reason!(reason)
      text = reason.to_s.strip
      raise DomainError.new("A reason is required", code: "validation_error") if text.blank?

      text
    end

    def self.search(query:)
      term = query.to_s.strip
      users = if term.blank?
        User.none
      else
        User.left_joins(:profile).where(
          "users.email ILIKE :q OR profiles.display_name ILIKE :q",
          q: "%#{ActiveRecord::Base.sanitize_sql_like(term)}%"
        ).limit(25)
      end
      orgs = if term.blank?
        Organization.none
      else
        Organization.where("name ILIKE ?", "%#{ActiveRecord::Base.sanitize_sql_like(term)}%").limit(25)
      end

      {
        users: users.map { |user| user_summary(user) },
        organizations: orgs.map { |org| organization_summary(org) }
      }
    end

    def self.user_summary(user)
      {
        id: user.id,
        email: user.email,
        status: user.status,
        age_status: user.age_status,
        display_name: user.profile&.display_name,
        deletion_recovery: user.in_deletion_recovery?,
        workspaces: user.usable_workspaces.map { |workspace|
          status = workspace.personal? ? "active" : workspace.organization&.workspace_status
          { id: workspace.id, name: workspace.name, kind: workspace.kind, status: status }
        }
      }
    end

    def self.organization_summary(organization)
      {
        id: organization.id,
        name: organization.name,
        workspace_status: organization.workspace_status,
        workspace_disabled: organization.workspace_disabled?
      }
    end

    def self.resend_invitation!(actor:, invitation_id:)
      invitation = Invitation.find_by(id: invitation_id) || ProjectInvitation.find(invitation_id)
      if invitation.is_a?(Invitation)
        raw = invitation.rotate_token!
        notification = Notification.find_by(source_type: "Invitation", source_id: invitation.id, event_key: "organization_invitation")
        if notification
          notification.update!(email_status: "pending", payload: notification.payload.merge("token" => raw))
          Notifications::EnqueueDelivery.call(notification: notification)
        end
      else
        notification = Notification.find_by(source_type: "ProjectInvitation", source_id: invitation.id, event_key: "project_invitation")
        if notification
          notification.update!(email_status: "pending")
          Notifications::EnqueueDelivery.call(notification: notification)
        end
      end
      Audit.record!(actor: actor, action: "invitation_resend", target: invitation, reason: "resend")
      invitation
    end

    def self.link_account!(actor:, user:, firebase_uid:, confirm_email:)
      raise DomainError.new("Email does not match this account", code: "validation_error") if confirm_email.to_s.strip.downcase != user.email
      raise DomainError.new("firebase_uid is required", code: "validation_error") if firebase_uid.blank?

      user.update!(firebase_uid: firebase_uid)
      Audit.record!(actor: actor, action: "account_link", target: user, reason: "email_match")
      user
    end

    def self.reject_slug!
      raise DomainError.new("Slug correction is not available", code: "validation_error")
    end

    def self.suspend!(actor:, user:, reason:)
      text = require_reason!(reason)
      user.update!(status: User::SUSPENDED)
      Notifications::Hook.emit(
        event_key: "suspension",
        actor: actor,
        recipients: [ user ],
        source: user,
        payload: {}
      )
      Audit.record!(actor: actor, action: "suspend", target: user, reason: text)
      user
    end

    def self.start_deletion!(actor:, user:, reason:)
      text = require_reason!(reason)
      user.update!(deletion_requested_at: Time.current, deletion_cancelled_at: nil)
      Audit.record!(actor: actor, action: "deletion_start", target: user, reason: text)
      user
    end

    def self.cancel_deletion!(actor:, user:, reason:)
      text = require_reason!(reason)
      raise DomainError.new("Account is not in deletion recovery", code: "validation_error") unless user.in_deletion_recovery?

      user.update!(deletion_cancelled_at: Time.current)
      Audit.record!(actor: actor, action: "deletion_cancel", target: user, reason: text)
      user
    end

    def self.adjust_credits!(actor:, owner:, amount:, direction:, reason:)
      text = require_reason!(reason)
      amount = amount.to_i
      raise DomainError.new("Amount must be positive", code: "validation_error") if amount <= 0

      if direction == "grant"
        Credits::StaffGrant.call(owner: owner, amount: amount, reason: text, actor: actor)
      elsif direction == "remove"
        Credits::StaffRemoval.call(owner: owner, amount: amount, reason: text, actor: actor)
      else
        raise DomainError.new("Direction must be grant or remove", code: "validation_error")
      end
      Audit.record!(actor: actor, action: "credit_#{direction}", target: owner, reason: text)
      Credits::Balance.remaining(owner: owner)
    end

    def self.approve_refund!(actor:, refund_request:, reason:)
      text = require_reason!(reason)
      result = Billing::ApproveRefundRequest.call(refund_request: refund_request, actor_user: actor)
      Audit.record!(actor: actor, action: "refund_approve", target: refund_request, reason: text)
      result
    end

    def self.update_upgrade_request!(actor:, request:, status:)
      unless [ OrganizationUpgradeRequest::STATUS_CONTACTED, OrganizationUpgradeRequest::STATUS_CLOSED ].include?(status)
        raise DomainError.new("Status must be contacted or closed", code: "validation_error")
      end

      request.update!(status: status)
      Audit.record!(actor: actor, action: "upgrade_request_status", target: request, reason: status)
      request
    end

    def self.hide_review!(actor:, review:, reason:)
      text = require_reason!(reason)
      review.update!(hidden_at: Time.current)
      Audit.record!(actor: actor, action: "review_hide", target: review, reason: text)
      review
    end

    def self.remove_message!(actor:, message:, reason:)
      text = require_reason!(reason)
      message.update!(removed_at: Time.current)
      Audit.record!(actor: actor, action: "message_remove", target: message, reason: text)
      message
    end

    def self.archive_project!(actor:, project:, reason:)
      text = require_reason!(reason)
      project.update!(status: Project::STATUS_ARCHIVED)
      Audit.record!(actor: actor, action: "project_archive", target: project, reason: text)
      project
    end

    def self.inspect_file!(actor:, blob:, reason:)
      text = require_reason!(reason)
      Audit.record!(actor: actor, action: "file_inspect", target: blob, reason: text)
      { signed_id: blob.signed_id(expires_in: 15.minutes), expires_in: 900 }
    end

    def self.date_of_birth!(actor:, user:, reason:)
      text = require_reason!(reason)
      Audit.record!(actor: actor, action: "date_of_birth_read", target: user, reason: text)
      { user_id: user.id, date_of_birth: user.profile&.date_of_birth&.iso8601 }
    end

    def self.correct_ai_review!(actor:, review:, decision:, reason:)
      text = require_reason!(reason)
      unless %w[approved corrections_requested].include?(decision)
        raise DomainError.new("Decision must be approved or corrections_requested", code: "validation_error")
      end

      review.update!(decision: decision, status: AiReview::STATUS_SUCCEEDED)
      Audit.record!(actor: actor, action: "ai_review_correction", target: review, reason: text)
      review
    end

    def self.start_impersonation!(actor:, target:, reason:)
      text = require_reason!(reason)
      session = ImpersonationSession.create!(
        actor: actor,
        target: target,
        reason: text,
        expires_at: ImpersonationSession::DURATION.from_now
      )
      Audit.record!(actor: actor, action: "impersonation_start", target: session, reason: text)
      session
    end

    def self.exit_impersonation!(actor:, session:)
      raise DomainError.new("Impersonation session is not active", code: "validation_error") unless session.actor_id == actor.id && session.active?

      session.update!(ended_at: Time.current)
      Audit.record!(actor: actor, action: "impersonation_end", target: session, reason: "exit")
      session
    end

    def self.queues
      {
        failed_jobs: failed_jobs,
        failed_emails: Notification.where(email_status: "failed").order(created_at: :desc).limit(50).map { |note|
          { id: note.id, event_key: note.event_key, created_at: note.created_at }
        },
        escalations: Escalation.where(status: Escalation::STATUS_OPEN).limit(50).map { |row|
          { id: row.id, project_id: row.project_id, created_at: row.created_at }
        }
      }
    end

    def self.failed_jobs
      return [] unless defined?(SolidQueue::FailedExecution)

      SolidQueue::FailedExecution.order(created_at: :desc).limit(50).map do |row|
        { id: row.id, error: row.error.to_s.truncate(180), created_at: row.created_at }
      end
    rescue ActiveRecord::ActiveRecordError
      []
    end

    def self.audit_feed
      StaffAuditEvent.order(created_at: :desc).limit(100).map do |event|
        { id: event.id, action: event.action, target_type: event.target_type, target_id: event.target_id, reason: event.reason, created_at: event.created_at, actor_id: event.actor_id }
      end
    end
  end
end
