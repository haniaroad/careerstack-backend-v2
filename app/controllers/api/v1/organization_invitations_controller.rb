# frozen_string_literal: true

module Api
  module V1
    class OrganizationInvitationsController < BaseController
      def index
        access = Organizations::Access.staff!(user: current_user, organization_id: params[:organization_id])
        invitations = access.organization.invitations.includes(:program, created_by_user: :profile).order(created_at: :desc)
        invitations = invitations.where(program_id: params[:program_id]) if params[:program_id].present?
        render json: { invitations: invitations.map { |invitation| OrganizationInvitationSerializer.call(invitation) } }
      end
    end
  end
end
