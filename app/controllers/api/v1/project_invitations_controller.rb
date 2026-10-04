# frozen_string_literal: true

module Api
  module V1
    class ProjectInvitationsController < BaseController
      def index
        project = find_creator_project!
        invites = project.invitations.order(created_at: :desc)
        render json: { invitations: invites.map { |i| serialize(i) } }
      end

      def create
        project = find_creator_project!
        invitee = resolve_invitee!
        invitation = Projects::CreateInvitation.call(
          project: project,
          inviter: current_user,
          invitee: invitee,
          requested_role: params.require(:requested_role)
        )
        render json: { invitation: serialize(invitation) }, status: :created
      end

      def accept
        invitation = find_invitee_invitation!
        result = Projects::AcceptInvitation.call(invitation: invitation, user: current_user)
        render json: {
          invitation: serialize(result[:invitation]),
          project: ProjectSerializer.call(invitation.project.reload, viewer: current_user),
          session: SessionSerializer.new(current_user.reload).as_json
        }
      end

      def decline
        invitation = find_invitee_invitation!
        declined = Projects::DeclineInvitation.call(invitation: invitation, user: current_user)
        render json: { invitation: serialize(declined) }
      end

      private

      def require_workspace!
        workspace = current_user.resolved_active_workspace
        raise DomainError.new("No active workspace", code: "no_workspace") if workspace.nil?

        workspace
      end

      def resolve_invitee!
        if params[:invitee_email].present?
          email = params[:invitee_email].to_s.strip.downcase
          unless email.match?(URI::MailTo::EMAIL_REGEXP)
            raise DomainError.new("Enter a valid email address.", code: "validation_error")
          end
          if email == current_user.email.to_s.downcase
            raise DomainError.new("You can't invite yourself to this project.", code: "validation_error")
          end

          user = User.where("LOWER(email) = ?", email).first
          if user.nil?
            raise DomainError.new(
              "That person needs a CareerStack account before you can invite them.",
              code: "invitee_not_found"
            )
          end

          return user
        end

        User.find(params.require(:invitee_id))
      end

      def find_creator_project!
        workspace = require_workspace!
        project = Project.in_workspace(workspace).find_by(id: params[:project_id], creator_id: current_user.id)
        raise ActiveRecord::RecordNotFound if project.nil?

        project
      end

      def find_invitee_invitation!
        invitation = ProjectInvitation.find_by(id: params[:id])
        raise ActiveRecord::RecordNotFound if invitation.nil?
        raise DomainError.new("Only the invitee can respond", code: "forbidden", status: :forbidden) unless invitation.invitee_id == current_user.id

        invitation
      end

      def serialize(invitation)
        {
          id: invitation.id,
          project_id: invitation.project_id,
          inviter_id: invitation.inviter_id,
          invitee_id: invitation.invitee_id,
          invitee_email: invitation.invitee&.email,
          requested_role: invitation.requested_role,
          status: invitation.status,
          created_at: invitation.created_at,
          responded_at: invitation.responded_at
        }
      end
    end
  end
end
