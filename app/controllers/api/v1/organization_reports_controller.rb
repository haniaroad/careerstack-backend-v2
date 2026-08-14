# frozen_string_literal: true

module Api
  module V1
    class OrganizationReportsController < BaseController
      def index
        access = Organizations::Access.staff!(user: current_user, organization_id: params[:organization_id])
        reports = access.organization.organization_reports.includes(:program).order(created_at: :desc)
        render json: { reports: reports.map { |report| OrganizationReportSerializer.call(report) } }
      end

      def create
        access = Organizations::Access.staff!(user: current_user, organization_id: params[:organization_id])
        report = OrganizationReports::Create.call(
          actor: current_user,
          organization: access.organization,
          params: report_params
        )
        render json: { report: OrganizationReportSerializer.call(report) }, status: :created
      end

      def show
        report = find_report!
        Organizations::Access.staff!(user: current_user, organization_id: report.organization_id)
        render json: { report: OrganizationReportSerializer.call(report) }
      end

      def generate
        report = find_report!
        Organizations::Access.staff!(user: current_user, organization_id: report.organization_id)
        updated = OrganizationReports::EnqueueGenerate.call(report: report, actor: current_user)
        render json: { report: OrganizationReportSerializer.call(updated) }
      end

      def download
        report = find_report!
        Organizations::Access.staff!(user: current_user, organization_id: report.organization_id)
        result = OrganizationReports::Download.call(
          report: report,
          actor: current_user,
          confirm_minor_names: ActiveModel::Type::Boolean.new.cast(params[:confirm_minor_names]),
          host: request.host_with_port
        )
        render json: { url: result[:url], expires_at: result[:expires_at] }
      end

      def outcome_aggregates
        access = Organizations::Access.staff!(user: current_user, organization_id: params[:organization_id])
        aggregates = OrganizationReports::OutcomeAggregates.call(
          organization: access.organization,
          program_id: params[:program_id]
        )
        render json: { outcomes: aggregates }
      end

      private

      def find_report!
        OrganizationReport.find(params[:id])
      end

      def report_params
        params.permit(:period_starts_on, :period_ends_on, :program_id, :format, :aggregate_only)
      end
    end
  end
end
