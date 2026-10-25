# frozen_string_literal: true

module Onboarding
  # A staff-provisioned organization member already belongs to the organization.
  # They still complete the organization profile and date-of-birth onboarding
  # so a minor is not asked to attest that they are an adult.
  class ProvisionedMember
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

      membership = @user.organization_memberships.active.includes(:organization).first
      if membership.nil?
        raise Error.new("This account is not part of an organization yet", code: "validation_error")
      end

      organization = membership.organization
      date_of_birth = parse_date_of_birth!(@params[:date_of_birth])
      guard_minimum_registration_age!(date_of_birth, organization.timezone)
      age_status = AgeStatusCalculator.call(date_of_birth: date_of_birth, timezone: organization.timezone)
      profile = ProfileInput.new(@params).validate!

      ActiveRecord::Base.transaction do
        @user.create_profile!(profile.attributes.merge(date_of_birth: date_of_birth))
        preference = @user.age_visibility_preference || @user.create_age_visibility_preference!
        organization_workspace = Workspaces::EnsureOrganization.call(organization: organization)

        @user.update!(
          status: User::ACTIVE,
          onboarding_path: "organization_invited",
          age_status: age_status,
          terms_accepted_at: Time.current,
          active_workspace_id: organization_workspace&.id
        )

        if @user.adult?
          preference.confirm_public_identity!
          personal = Workspaces::EnsurePersonal.call(user: @user)
          Credits::GrantPersonalTrial.call(user: @user)
          @user.update!(active_workspace_id: personal.id) if personal
        end
      end

      Notifications::Hook.emit(
        event_key: "welcome",
        actor: nil,
        recipients: [ @user ],
        source: @user,
        payload: {}
      )

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
