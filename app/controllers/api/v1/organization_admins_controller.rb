# frozen_string_literal: true

module Api
  module V1
    class OrganizationAdminsController < BaseController
      def show
        access = Organizations::Access.staff!(user: current_user, organization_id: params[:organization_id])
        render json: Organizations::AdminShow.call(organization: access.organization, membership: access.membership)
      end
    end
  end
end
