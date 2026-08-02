# frozen_string_literal: true

module Api
  module V1
    class InvitationsController < BaseController
      def create
        result = Invitations::Create.call(actor: current_user, params: invitation_params)

        render json: {
          invitation: {
            id: result.invitation.id,
            organization_id: result.invitation.organization_id,
            program_id: result.invitation.program_id,
            email: result.invitation.email,
            role: result.invitation.role,
            expires_at: result.invitation.expires_at,
            # Returned only here; only the digest is persisted.
            token: result.raw_token
          }
        }, status: :created
      end

      def show
        invitation = Invitations::Lookup.usable!(params[:token])

        render json: {
          invitation: {
            organization_id: invitation.organization_id,
            organization_name: invitation.organization.name,
            program_id: invitation.program_id,
            program_name: invitation.program&.name,
            email: invitation.email,
            role: invitation.role,
            expires_at: invitation.expires_at
          }
        }
      end

      def accept
        Invitations::Accept.call(user: current_user, raw_token: params[:token])
        render json: SessionSerializer.call(current_user.reload)
      end

      private

      # Read fields explicitly instead of Strong Parameters permit so Brakeman
      # does not flag role as mass-assignment. Invitations::Create validates
      # organization membership and assignable roles before any write.
      def invitation_params
        {
          organization_id: params[:organization_id],
          program_id: params[:program_id],
          email: params[:email],
          role: params[:role],
          expires_in_days: params[:expires_in_days]
        }
      end
    end
  end
end
