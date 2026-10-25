# frozen_string_literal: true

module Api
  module V1
    class PlatformAdminController < BaseController
      HIGH_RISK = %i[
        suspend destroy_user cancel_deletion credits refund upgrade_request
        hide_review remove_message archive_project inspect_file date_of_birth
        correct_ai_review start_impersonation
        provision_user import_users provision_organization
        provision_project update_project duplicate_project
        add_project_member remove_project_member
      ].freeze

      before_action :require_platform_admin
      before_action :require_reauthentication, only: HIGH_RISK

      def session
        render json: { platform_admin: true }
      end

      def search
        render json: PlatformAdmin::Operations.search(query: params[:q])
      end

      def resend_invitation
        invitation = PlatformAdmin::Operations.resend_invitation!(actor: current_user, invitation_id: params[:id])
        render json: { id: invitation.id, type: invitation.class.name }
      end

      def link_account
        user = User.find(params[:user_id])
        PlatformAdmin::Operations.link_account!(
          actor: current_user,
          user: user,
          firebase_uid: params[:firebase_uid],
          confirm_email: params[:confirm_email]
        )
        render json: PlatformAdmin::Operations.user_summary(user.reload)
      end

      def reject_slug
        PlatformAdmin::Operations.reject_slug!
      end

      def suspend
        user = User.find(params[:user_id])
        PlatformAdmin::Operations.suspend!(actor: current_user, user: user, reason: params[:reason])
        render json: PlatformAdmin::Operations.user_summary(user.reload)
      end

      def destroy_user
        user = User.find(params[:user_id])
        PlatformAdmin::Operations.start_deletion!(actor: current_user, user: user, reason: params[:reason])
        render json: { id: user.id, deletion_requested_at: user.deletion_requested_at, status: user.status }
      end

      def cancel_deletion
        user = User.find(params[:user_id])
        PlatformAdmin::Operations.cancel_deletion!(actor: current_user, user: user, reason: params[:reason])
        render json: { id: user.id, deletion_recovery: user.in_deletion_recovery? }
      end

      def credits
        owner = find_ledger_owner!
        balance = PlatformAdmin::Operations.adjust_credits!(
          actor: current_user,
          owner: owner,
          amount: params[:amount],
          direction: params[:direction],
          reason: params[:reason]
        )
        render json: { balance: balance }
      end

      def refund
        request_record = CreditRefundRequest.find(params[:id])
        result = PlatformAdmin::Operations.approve_refund!(actor: current_user, refund_request: request_record, reason: params[:reason])
        render json: { id: result[:refund_request].id, status: result[:refund_request].status }
      end

      def upgrade_request
        record = OrganizationUpgradeRequest.find(params[:id])
        updated = PlatformAdmin::Operations.update_upgrade_request!(actor: current_user, request: record, status: params[:status])
        render json: { id: updated.id, status: updated.status }
      end

      def hide_review
        review = PeerReview.find(params[:id])
        PlatformAdmin::Operations.hide_review!(actor: current_user, review: review, reason: params[:reason])
        render json: { id: review.id, hidden_at: review.hidden_at }
      end

      def remove_message
        message = ProjectMessage.find(params[:id])
        PlatformAdmin::Operations.remove_message!(actor: current_user, message: message, reason: params[:reason])
        render json: { id: message.id, removed_at: message.removed_at }
      end

      def archive_project
        project = Project.find(params[:id])
        PlatformAdmin::Operations.archive_project!(actor: current_user, project: project, reason: params[:reason])
        render json: { id: project.id, status: project.status, creator_status: project.creator.status }
      end

      def inspect_file
        blob = ActiveStorage::Blob.find(params[:id])
        render json: PlatformAdmin::Operations.inspect_file!(actor: current_user, blob: blob, reason: params[:reason])
      end

      def date_of_birth
        if params[:user_ids].present?
          raise DomainError.new("Bulk date of birth export is not allowed", code: "forbidden", status: :forbidden)
        end

        user = User.find(params[:user_id])
        render json: PlatformAdmin::Operations.date_of_birth!(actor: current_user, user: user, reason: params[:reason])
      end

      def correct_ai_review
        review = AiReview.find(params[:id])
        updated = PlatformAdmin::Operations.correct_ai_review!(
          actor: current_user,
          review: review,
          decision: params[:decision],
          reason: params[:reason]
        )
        render json: { id: updated.id, decision: updated.decision }
      end

      def start_impersonation
        target = User.find(params[:user_id])
        session = PlatformAdmin::Operations.start_impersonation!(actor: current_user, target: target, reason: params[:reason])
        render json: { session_id: session.id, expires_at: session.expires_at }, status: :created
      end

      def exit_impersonation
        session = ImpersonationSession.find(params[:id])
        PlatformAdmin::Operations.exit_impersonation!(actor: current_user, session: session)
        render json: { ended: true }
      end

      def queues
        render json: PlatformAdmin::Operations.queues
      end

      def audit
        render json: { events: PlatformAdmin::Operations.audit_feed }
      end

      def update_audit
        event = StaffAuditEvent.find(params[:id])
        event.update!(reason: "changed")
        render json: { id: event.id }
      end

      def destroy_audit
        event = StaffAuditEvent.find(params[:id])
        event.destroy!
        head :no_content
      end

      def organizations
        records = Organization.order(:name).limit(200)
        render json: {
          organizations: records.map { |organization|
            { id: organization.id, name: organization.name, workspace_status: organization.workspace_status }
          }
        }
      end

      def organization
        organization = Organization.find(params[:id])
        render json: { organization: organization_detail(organization) }
      end

      def provision_user
        require_reason!
        result = PlatformAdmin::ProvisionAccount.call!(
          actor: current_user,
          email: params[:email],
          organization_id: params[:organization_id],
          role: params[:role],
          reason: params[:reason]
        )
        render json: result, status: result[:status] == "created" ? :created : :ok
      end

      def import_users
        require_reason!
        result = PlatformAdmin::ImportAccounts.call!(
          actor: current_user,
          csv_text: params[:csv],
          organization_id: params[:organization_id],
          reason: params[:reason]
        )
        render json: result
      end

      def provision_organization
        require_reason!
        admin = User.find(params[:admin_user_id])
        result = Organizations::CreateOrganization.call(user: admin, params: organization_params)
        PlatformAdmin::Audit.record!(
          actor: current_user,
          action: "provision_organization",
          target: result.organization,
          reason: params[:reason]
        )
        render json: {
          id: result.organization.id,
          name: result.organization.name,
          trial_granted: result.trial_granted
        }, status: :created
      end

      def project
        render json: { project: PlatformAdmin::ProvisionProject.show(Project.find(params[:id])) }
      end

      def provision_project
        organization = Organization.find(params[:organization_id])
        project = PlatformAdmin::ProvisionProject.create!(
          actor: current_user,
          organization: organization,
          params: project_params,
          reason: params[:reason]
        )
        render json: { project: project }, status: :created
      end

      def update_project
        project = Project.find(params[:id])
        updated = PlatformAdmin::ProvisionProject.update!(
          actor: current_user,
          project: project,
          params: project_params,
          reason: params[:reason]
        )
        render json: { project: updated }
      end

      def duplicate_project
        project = Project.find(params[:id])
        copy = PlatformAdmin::ProvisionProject.duplicate!(
          actor: current_user,
          project: project,
          params: project_params,
          reason: params[:reason]
        )
        render json: { project: copy }, status: :created
      end

      def add_project_member
        project = Project.find(params[:id])
        updated = PlatformAdmin::ProvisionProject.add_member!(
          actor: current_user,
          project: project,
          user_id: params[:user_id],
          participant_role: params[:participant_role],
          reason: params[:reason]
        )
        render json: { project: updated }
      end

      def remove_project_member
        project = Project.find(params[:id])
        updated = PlatformAdmin::ProvisionProject.remove_member!(
          actor: current_user,
          project: project,
          user_id: params[:user_id],
          reason: params[:reason]
        )
        render json: { project: updated }
      end

      private

      def require_platform_admin
        PlatformAdmin::Access.authorize!(user: current_user, identity: current_identity)
      end

      def require_reauthentication
        return if PlatformAdmin::Access.reauthenticated?(current_identity)

        render_error(code: "reauthentication_required", message: "Sign in again before this action", status: :forbidden)
      end

      def find_ledger_owner!
        case params[:owner_type]
        when "user"
          User.find(params[:owner_id])
        when "organization"
          Organization.find(params[:owner_id])
        else
          raise DomainError.new("owner_type must be user or organization", code: "validation_error")
        end
      end

      def require_reason!
        return if params[:reason].present?

        raise DomainError.new("A reason is required", code: "validation_error")
      end

      def organization_params
        params.permit(
          :name, :country, :state_region, :timezone,
          :structure_term_id, :structure_other,
          :primary_goal_term_id, :primary_goal_other,
          :website, :logo_url, :expected_participant_range
        )
      end

      def project_params
        params.permit(
          :creator_id, :title, :summary, :ends_on, :visibility, :mode,
          :joining_mode, :capacity, :program_id, :program_name,
          skills: [],
          roles_needed: [],
          members: [ :user_id, :participant_role ],
          tasks: [ :id, :title, :acceptance_criteria, :due_on, :assignee_id ]
        )
      end

      def organization_detail(organization)
        {
          id: organization.id,
          name: organization.name,
          programs: organization.programs.order(:name).map { |program|
            { id: program.id, name: program.name, status: program.status }
          },
          members: organization.organization_memberships.active.includes(user: :profile).map { |membership|
            user = membership.user
            {
              user_id: user.id,
              email: user.email,
              display_name: user.profile&.display_name,
              role: membership.role,
              onboarded_adult: user.status == User::ACTIVE && user.adult?
            }
          },
          projects: PlatformAdmin::ProvisionProject.list(organization: organization)
        }
      end
    end
  end
end
