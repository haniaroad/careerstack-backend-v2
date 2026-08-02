# frozen_string_literal: true

module Api
  module V1
    class OrganizationsController < BaseController
      def create
        result = Organizations::CreateOrganization.call(user: current_user, params: organization_params)

        render json: {
          organization: {
            id: result.organization.id,
            name: result.organization.name,
            workspace_id: result.workspace&.id
          },
          organization_trial_granted: result.trial_granted,
          session: SessionSerializer.call(current_user.reload)
        }, status: :created
      end

      private

      def organization_params
        params.permit(
          :name, :structure_term_id, :structure_other, :country, :state_region,
          :primary_goal_term_id, :primary_goal_other, :website, :logo_url,
          :expected_participant_range, :timezone
        )
      end
    end
  end
end
