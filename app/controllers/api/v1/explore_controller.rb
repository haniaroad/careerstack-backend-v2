# frozen_string_literal: true

module Api
  module V1
    class ExploreController < BaseController
      def projects
        require_onboarded!
        render json: Explore::ProjectsQuery.call(
          viewer: current_user,
          workspace: require_workspace!,
          filters: project_filters,
          page: params[:page],
          per_page: params[:per_page]
        )
      end

      def people
        require_onboarded!
        render json: Explore::PeopleQuery.call(
          viewer: current_user,
          filters: people_filters,
          page: params[:page],
          per_page: params[:per_page]
        )
      end

      def invite_options
        require_onboarded!
        target = User.find_by(id: params.require(:user_id))
        raise ActiveRecord::RecordNotFound if target.nil?

        render json: Explore::InviteOptions.call(viewer: current_user, target: target)
      end

      private

      def require_onboarded!
        return unless current_user.pending_onboarding?

        raise DomainError.new("Complete onboarding before exploring", code: "onboarding_required", status: :forbidden)
      end

      def require_workspace!
        workspace = current_user.resolved_active_workspace
        raise DomainError.new("No active workspace", code: "no_workspace") if workspace.nil?

        workspace
      end

      def project_filters
        params.permit(:q, :skill, :role).to_h.symbolize_keys
      end

      def people_filters
        params.permit(:name, :skill, :role, :experience, :location, :organization).to_h.symbolize_keys
      end
    end
  end
end
