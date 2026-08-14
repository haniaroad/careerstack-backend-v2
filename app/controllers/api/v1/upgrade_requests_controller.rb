# frozen_string_literal: true

module Api
  module V1
    class UpgradeRequestsController < BaseController
      def show
        access = Organizations::Access.admin!(user: current_user, organization_id: params[:organization_id])
        request = access.organization.open_upgrade_request
        render json: { upgrade_request: request && UpgradeRequestSerializer.call(request) }
      end

      def upsert
        access = Organizations::Access.admin!(user: current_user, organization_id: params[:organization_id])
        request = UpgradeRequests::Upsert.call(
          organization: access.organization,
          admin: current_user,
          params: params.permit(:expected_participants, :expected_projects_or_cohorts, :timeline, :notes)
        )
        render json: { upgrade_request: UpgradeRequestSerializer.call(request) }
      end
    end
  end
end
