# frozen_string_literal: true

module Onboarding
  # Organization-invited path: a valid invitation plus date of birth. The DOB is
  # stored on the profile and immediately reduced to a derived age status, which
  # is the only form the rest of the application sees (D-6).
  class OrganizationInvited
    def self.call(user:, params:)
      new(user: user, params: params).call
    end

    def initialize(user:, params:)
      @user = user
      @params = params.to_h.with_indifferent_access
    end

    def call
      raise Error.new("Onboarding is already complete", code: "already_onboarded") unless @user.pending_onboarding?
      raise Error, "Terms acceptance is required" unless truthy?(@params[:terms_accepted])

      invitation = Invitations::Lookup.usable!(@params[:invitation_token])
      organization = invitation.organization
      date_of_birth = parse_date_of_birth!(@params[:date_of_birth])
      guard_minimum_registration_age!(date_of_birth, organization.timezone)

      age_status = AgeStatusCalculator.call(
        date_of_birth: date_of_birth,
        timezone: organization.timezone
      )

      profile = ProfileInput.new(@params).validate!

      ActiveRecord::Base.transaction do
        @user.create_profile!(profile.attributes.merge(date_of_birth: date_of_birth))
        @user.create_age_visibility_preference! if @user.age_visibility_preference.blank?

        OrganizationMembership.create!(
          organization: organization,
          user: @user,
          role: invitation.role,
          program: invitation.program
        )
        invitation.update!(accepted_at: Time.current, accepted_by_user: @user)
        organization_workspace = Workspaces::EnsureOrganization.call(organization: organization)

        @user.update!(
          status: "active",
          onboarding_path: "organization_invited",
          age_status: age_status,
          terms_accepted_at: Time.current,
          active_workspace_id: organization_workspace&.id
        )

        # Minors and unknown-age users get organization-private participation
        # only: no Personal workspace and no personal trial credit.
        if @user.adult?
          personal = Workspaces::EnsurePersonal.call(user: @user)
          Credits::GrantPersonalTrial.call(user: @user)
          @user.update!(active_workspace_id: personal.id) if personal
        end
      end

      @user.reload
    end

    private

    def truthy?(value)
      ActiveModel::Type::Boolean.new.cast(value)
    end

    def parse_date_of_birth!(value)
      raise Error, "date_of_birth is required" if value.blank?

      date = Date.iso8601(value.to_s)
      raise Error, "date_of_birth cannot be in the future" if date > Date.current

      date
    rescue Date::Error
      raise Error, "date_of_birth must be an ISO 8601 date (YYYY-MM-DD)"
    end

    def guard_minimum_registration_age!(date_of_birth, timezone)
      return unless AgeStatusCalculator.below_minimum_registration_age?(
        date_of_birth: date_of_birth,
        timezone: timezone
      )

      raise Error.new(
        "Users under #{AgeStatusCalculator::MINIMUM_REGISTRATION_AGE} cannot register",
        code: "below_minimum_age"
      )
    end
  end
end
