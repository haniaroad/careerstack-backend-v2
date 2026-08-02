# frozen_string_literal: true

module Api
  module V1
    class OnboardingController < BaseController
      PROFILE_FIELDS = %i[
        display_name country state_region career_goal
        current_role_term_id current_role_other experience_level
        target_role_term_id target_role_other
        bio image_url github_url linkedin_url portfolio_url
      ].freeze

      def independent
        user = Onboarding::Independent.call(user: current_user, params: independent_params)
        render json: SessionSerializer.call(user), status: :created
      end

      def organization_invited
        user = Onboarding::OrganizationInvited.call(user: current_user, params: invited_params)
        render json: SessionSerializer.call(user), status: :created
      end

      private

      def independent_params
        params.permit(:age_attested, :terms_accepted, *PROFILE_FIELDS, interests: [])
      end

      def invited_params
        params.permit(
          :invitation_token, :terms_accepted, :date_of_birth, *PROFILE_FIELDS, interests: []
        )
      end
    end
  end
end
