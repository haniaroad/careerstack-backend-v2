# frozen_string_literal: true

module Api
  module V1
    class ProjectsController < BaseController
      def index
        workspace = require_workspace!
        projects = visible_projects(workspace).order(updated_at: :desc)
        render json: { projects: projects.map { |p| ProjectSerializer.call(p, include_tasks: false) } }
      end

      def show
        project = find_visible_project!
        render json: { project: ProjectSerializer.call(project) }
      end

      def create
        workspace = require_workspace!
        project = Projects::CreateDraft.call(
          user: current_user,
          workspace: workspace,
          title: params.require(:title),
          summary: params[:summary],
          skills: params[:skills]
        )
        render json: { project: ProjectSerializer.call(project) }, status: :created
      end

      def update
        project = find_creator_draft!
        updated = Projects::UpdateDraft.call(
          project: project,
          user: current_user,
          title: params[:title],
          summary: params.key?(:summary) ? params[:summary] : :unchanged,
          skills: params.key?(:skills) ? params[:skills] : :unchanged,
          objective: params.key?(:objective) ? params[:objective] : :unchanged,
          project_type: params.key?(:project_type) ? params[:project_type] : :unchanged,
          expected_duration: params.key?(:expected_duration) ? params[:expected_duration] : :unchanged,
          ends_on: params.key?(:ends_on) ? params[:ends_on] : :unchanged,
          definition_of_done: params.key?(:definition_of_done) ? params[:definition_of_done] : :unchanged,
          roles_needed: params.key?(:roles_needed) ? params[:roles_needed] : :unchanged,
          proposed_tasks: params.key?(:proposed_tasks) ? params[:proposed_tasks] : :unchanged,
          submission_expectations: params.key?(:submission_expectations) ? params[:submission_expectations] : :unchanged
        )
        render json: { project: ProjectSerializer.call(updated) }
      end

      def destroy
        project = find_creator_draft!
        Projects::DiscardDraft.call(project: project, user: current_user)
        head :no_content
      end

      def confirm
        project = find_creator_project!
        confirmed = Projects::Confirm.call(project: project, user: current_user)
        render json: {
          project: ProjectSerializer.call(confirmed),
          session: SessionSerializer.new(current_user.reload).as_json
        }
      end

      def cancel
        project = find_creator_project!
        cancelled = Projects::Cancel.call(project: project, user: current_user)
        render json: {
          project: ProjectSerializer.call(cancelled),
          session: SessionSerializer.new(current_user.reload).as_json
        }
      end

      private

      def require_workspace!
        workspace = current_user.resolved_active_workspace
        raise DomainError.new("No active workspace", code: "no_workspace") if workspace.nil?

        workspace
      end

      def visible_projects(workspace)
        Project.in_workspace(workspace).where(
          "creator_id = :uid OR id IN (SELECT project_id FROM project_memberships WHERE user_id = :uid)",
          uid: current_user.id
        )
      end

      def find_visible_project!
        workspace = require_workspace!
        project = visible_projects(workspace).find_by(id: params[:id])
        raise ActiveRecord::RecordNotFound if project.nil?

        project
      end

      def find_creator_project!
        workspace = require_workspace!
        project = Project.in_workspace(workspace).find_by(id: params[:id], creator_id: current_user.id)
        raise ActiveRecord::RecordNotFound if project.nil?

        project
      end

      def find_creator_draft!
        project = find_creator_project!
        raise DomainError.new("Only draft projects can be modified this way", code: "validation_error") unless project.draft?

        project
      end
    end
  end
end
