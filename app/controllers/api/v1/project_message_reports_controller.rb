# frozen_string_literal: true

module Api
  module V1
    class ProjectMessageReportsController < BaseController
      def create
        message = ProjectMessage.find(params[:message_id] || params[:id])
        report = ProjectMessages::CreateReport.call(
          message: message,
          actor: current_user,
          report_type: params.require(:report_type),
          reason_category: params.require(:reason_category),
          details: params[:details]
        )
        render json: {
          report: {
            id: report.id,
            project_message_id: report.project_message_id,
            report_type: report.report_type,
            reason_category: report.reason_category,
            status: report.status,
            created_at: report.created_at
          }
        }, status: :created
      end
    end
  end
end
