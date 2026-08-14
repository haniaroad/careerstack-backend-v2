# frozen_string_literal: true

module Api
  module V1
    class CreditsController < BaseController
      def show
        owner = resolve_owner!
        render json: { credits: Credits::Balance.summary(owner: owner) }
      end

      def history
        owner = resolve_owner!
        if owner.is_a?(Organization)
          membership = current_user.membership_for(owner)
          unless membership&.can_view_credit_history?
            return render_forbidden("Only organization administrators can view credit history")
          end
        end
        render json: { entries: Credits::History.call(owner: owner) }
      end

      private

      def resolve_owner!
        workspace = current_user.resolved_active_workspace
        raise DomainError.new("No active workspace", code: "no_workspace", status: :unprocessable_entity) if workspace.nil?

        if workspace.organization_id.present?
          workspace.organization
        else
          current_user
        end
      end
    end
  end
end
