# frozen_string_literal: true

module Api
  module V1
    class ProjectApplicationsController < BaseController
      def index
        project = find_creator_project!
        apps = project.applications.order(created_at: :desc)
        render json: {
          applications: apps.map { |a| serialize(a) }
        }
      end

      def create
        project = find_joinable_project!
        application = Projects::SubmitApplication.call(
          project: project,
          user: current_user,
          requested_role: params.require(:requested_role),
          motivation: params.require(:motivation),
          availability_confirmed: params[:availability_confirmed],
          skills: params[:skills],
          portfolio_url: params[:portfolio_url],
          github_url: params[:github_url],
          resume_url: params[:resume_url]
        )
        render json: { application: serialize(application) }, status: :created
      end

      def approve
        application = find_creator_application!
        result = Projects::ApproveApplication.call(application: application, user: current_user)
        render json: {
          application: serialize(result[:application]),
          project: ProjectSerializer.call(application.project.reload, viewer: current_user),
          session: SessionSerializer.new(current_user.reload).as_json
        }
      end

      def reject
        application = find_creator_application!
        rejected = Projects::RejectApplication.call(
          application: application,
          user: current_user,
          reason: params.require(:reason)
        )
        render json: { application: serialize(rejected) }
      end

      private

      def require_workspace!
        workspace = current_user.resolved_active_workspace
        raise DomainError.new("No active workspace", code: "no_workspace") if workspace.nil?

        workspace
      end

      def find_joinable_project!
        project = Project.find_by(id: params[:project_id])
        raise ActiveRecord::RecordNotFound if project.nil?

        Projects::JoinEligibility.assert_can_join!(project: project, user: current_user)
        project
      end

      def find_workspace_project!
        workspace = require_workspace!
        project = Project.in_workspace(workspace).find_by(id: params[:project_id])
        raise ActiveRecord::RecordNotFound if project.nil?

        project
      end

      def find_creator_project!
        project = find_workspace_project!
        raise DomainError.new("Only the creator can manage applications", code: "forbidden", status: :forbidden) unless project.creator_id == current_user.id

        project
      end

      def find_creator_application!
        project = find_creator_project!
        application = project.applications.find_by(id: params[:id])
        raise ActiveRecord::RecordNotFound if application.nil?

        application
      end

      def serialize(application)
        {
          id: application.id,
          project_id: application.project_id,
          applicant_id: application.applicant_id,
          requested_role: application.requested_role,
          motivation: application.motivation,
          availability_confirmed: application.availability_confirmed,
          skills: application.skills,
          portfolio_url: application.portfolio_url,
          github_url: application.github_url,
          resume_url: application.resume_url,
          status: application.status,
          rejection_reason: application.rejection_reason,
          created_at: application.created_at,
          reviewed_at: application.reviewed_at
        }
      end
    end
  end
end
