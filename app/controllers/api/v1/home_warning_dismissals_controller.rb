# frozen_string_literal: true

module Api
  module V1
    class HomeWarningDismissalsController < BaseController
      def index
        rows = current_user.home_warning_dismissals.order(:dismissed_at)
        render json: {
          dismissals: rows.map { |row| { project_id: row.project_id, phase: row.phase } }
        }
      end

      def create
        dismissal = Home::DismissWarning.call(
          user: current_user,
          project_id: params.require(:project_id),
          phase: params.require(:phase)
        )
        render json: {
          dismissal: { project_id: dismissal.project_id, phase: dismissal.phase }
        }, status: :created
      end
    end
  end
end
