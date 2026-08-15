# frozen_string_literal: true

module Onboarding
  # Independent path: the user self-attests to being 18+, accepts terms, and
  # submits the minimum profile. No date of birth is ever collected here (D-6),
  # so the attestation alone establishes adult status.
  class Independent
    def self.call(user:, params:)
      new(user: user, params: params).call
    end

    def initialize(user:, params:)
      @user = user
      @params = params.to_h.with_indifferent_access
    end

    def call
      raise Error.new("Onboarding is already complete", code: "already_onboarded") unless @user.pending_onboarding?
      raise Error, "Age attestation is required" unless truthy?(@params[:age_attested])
      raise Error, "Terms acceptance is required" unless truthy?(@params[:terms_accepted])

      profile = ProfileInput.new(@params).validate!

      ActiveRecord::Base.transaction do
        @user.create_profile!(profile.attributes)
        preference = @user.age_visibility_preference || @user.create_age_visibility_preference!
        preference.confirm_public_identity!

        @user.update!(
          status: "active",
          onboarding_path: "independent",
          age_status: AgeStatusCalculator::ADULT,
          age_attested_at: Time.current,
          terms_accepted_at: Time.current
        )

        Workspaces::EnsurePersonal.call(user: @user)
        Credits::GrantPersonalTrial.call(user: @user)
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
  end
end
