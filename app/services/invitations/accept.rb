# frozen_string_literal: true

module Invitations
  # Accepts an invitation for a user who has already completed onboarding. Users
  # still in pending_onboarding accept through the organization-invited
  # onboarding endpoint instead, which also collects date of birth.
  class Accept
    def self.call(user:, raw_token:)
      new(user: user, raw_token: raw_token).call
    end

    def initialize(user:, raw_token:)
      @user = user
      @raw_token = raw_token
    end

    def call
      invitation = Invitations::Lookup.usable!(@raw_token)

      if @user.pending_onboarding?
        raise Error.new(
          "Complete organization-invited onboarding to use this invitation",
          code: "onboarding_required"
        )
      end

      ActiveRecord::Base.transaction do
        membership = @user.organization_memberships.find_or_initialize_by(organization_id: invitation.organization_id)
        if membership.new_record?
          membership.role = invitation.role
          membership.program = invitation.program
          membership.save!
        end

        Workspaces::EnsureOrganization.call(organization: invitation.organization)
        invitation.accept!(@user)
        membership
      end
    end
  end
end
