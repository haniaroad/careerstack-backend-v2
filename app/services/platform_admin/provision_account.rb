# frozen_string_literal: true

module PlatformAdmin
  # Creates a pending account for an email, optionally in an organization, and
  # sends the sign-in email. The existing welcome email still waits until
  # onboarding finishes. The first Google or magic-link sign-in attaches by email.
  class ProvisionAccount
    ROLES = OrganizationMembership::ROLES

    def self.call!(actor:, email:, organization_id: nil, role: nil, reason:)
      new(actor:, email:, organization_id:, role:, reason:).call!
    end

    def initialize(actor:, email:, organization_id:, role:, reason:)
      @actor = actor
      @email = email.to_s.strip.downcase
      @organization_id = organization_id.presence
      @role = role.to_s.strip.presence || OrganizationMembership::PARTICIPANT
      @reason = reason.to_s.strip
    end

    def call!
      validate!
      organization = find_organization
      existing = User.where("lower(email) = ?", @email).first

      if existing
        return attach_existing!(existing, organization)
      end

      user = nil
      ActiveRecord::Base.transaction do
        user = User.create!(
          firebase_uid: nil,
          email: @email,
          status: User::PENDING_ONBOARDING
        )
        add_membership!(user, organization) if organization
      end

      deliver_signin!(user, organization)
      Audit.record!(actor: @actor, action: "provision_user", target: user, reason: @reason)
      result(status: "created", user: user, message: "Account created. A sign-in email was sent.")
    end

    private

    def validate!
      raise DomainError.new("A reason is required", code: "validation_error") if @reason.blank?
      raise DomainError.new("Email is required", code: "validation_error") if @email.blank?
      unless @email.match?(URI::MailTo::EMAIL_REGEXP)
        raise DomainError.new("Email is not valid", code: "validation_error")
      end
      return if ROLES.include?(@role)

      raise DomainError.new("Role must be participant, manager, or admin", code: "validation_error")
    end

    def find_organization
      return nil if @organization_id.blank?

      Organization.find_by(id: @organization_id) ||
        raise(DomainError.new("Organization was not found", code: "not_found", status: :not_found))
    end

    def attach_existing!(user, organization)
      if organization && user.organization_memberships.active.exists?(organization_id: organization.id)
        return result(status: "already_exists", user: user, message: "That email already has an account in this organization.")
      end

      if organization
        ActiveRecord::Base.transaction { add_membership!(user, organization) }
        Audit.record!(actor: @actor, action: "provision_membership", target: user, reason: @reason)
        return result(status: "already_exists", user: user, message: "That email already has an account. They were added to the organization.")
      end

      result(status: "already_exists", user: user, message: "That email already has an account.")
    end

    def add_membership!(user, organization)
      if privileged_role? && !onboarded_adult?(user)
        raise DomainError.new(
          "Manager and admin require an onboarded adult. New accounts can be participants.",
          code: "validation_error"
        )
      end

      OrganizationMembership.create!(
        organization: organization,
        user: user,
        role: @role
      )
      workspace = Workspaces::EnsureOrganization.call(organization: organization)
      user.update!(active_workspace_id: workspace.id) if user.active_workspace_id.blank? && workspace
    end

    def privileged_role?
      @role.in?(OrganizationMembership::STAFF_ROLES)
    end

    def onboarded_adult?(user)
      user.status == User::ACTIVE && user.adult? && !user.pending_onboarding?
    end

    def deliver_signin!(user, organization)
      context = if organization
        "You were added to #{organization.name}."
      else
        "Finish your profile after you sign in."
      end
      Notifications::Hook.emit(
        event_key: "account_signin",
        actor: @actor,
        recipients: [ user ],
        source: user,
        organization: organization,
        payload: { "context" => context }
      )
    end

    def result(status:, user:, message:)
      {
        status: status,
        id: user.id,
        email: user.email,
        message: message
      }
    end
  end
end
