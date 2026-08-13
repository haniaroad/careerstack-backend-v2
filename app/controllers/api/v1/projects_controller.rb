# frozen_string_literal: true

module Api
  module V1
    class ProjectsController < BaseController
      def index
        workspace = require_workspace!
        projects = visible_projects(workspace).order(updated_at: :desc)
        projects.each { |p| evaluate_if_overdue!(p) }
        render json: { projects: projects.map { |p| ProjectSerializer.call(p, include_tasks: false, viewer: current_user) } }
      end

      def show
        project = find_visible_or_joinable_project!
        evaluate_if_overdue!(project)
        render json: { project: ProjectSerializer.call(project.reload, viewer: current_user) }
      end

      def create
        workspace = require_workspace!
        project = Projects::CreateDraft.call(
          user: current_user,
          workspace: workspace,
          title: params.require(:title),
          summary: params[:summary],
          skills: params[:skills],
          mode: params[:mode] || Project::MODE_SOLO,
          joining_mode: params[:joining_mode],
          capacity: params[:capacity],
          roles_needed: params[:roles_needed],
          visibility: params[:visibility]
        )
        render json: { project: ProjectSerializer.call(project, viewer: current_user) }, status: :created
      end

      def update
        project = find_creator_project!

        if project.draft?
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
            submission_expectations: params.key?(:submission_expectations) ? params[:submission_expectations] : :unchanged,
            mode: params.key?(:mode) ? params[:mode] : :unchanged,
            joining_mode: params.key?(:joining_mode) ? params[:joining_mode] : :unchanged,
            capacity: params.key?(:capacity) ? params[:capacity] : :unchanged,
            visibility: params.key?(:visibility) ? params[:visibility] : :unchanged
          )
          return render json: { project: ProjectSerializer.call(updated, viewer: current_user) }
        end

        if params.key?(:visibility)
          Projects::UpdateVisibility.call(
            project: project,
            user: current_user,
            visibility: params[:visibility]
          )
          project.reload
        end

        if project.active? && params.key?(:ends_on)
          project = Projects::UpdateEndsOn.call(
            project: project,
            user: current_user,
            ends_on: params[:ends_on]
          )
        elsif !params.key?(:visibility)
          raise DomainError.new("Only draft projects can be modified this way", code: "validation_error")
        end

        render json: { project: ProjectSerializer.call(project.reload, viewer: current_user) }
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
          project: ProjectSerializer.call(confirmed, viewer: current_user),
          session: SessionSerializer.new(current_user.reload).as_json
        }
      end

      def cancel
        project = find_creator_project!
        cancelled = Projects::Cancel.call(project: project, user: current_user)
        render json: {
          project: ProjectSerializer.call(cancelled, viewer: current_user),
          session: SessionSerializer.new(current_user.reload).as_json
        }
      end

      def convert_to_team
        project = find_creator_project!
        converted = Projects::ConvertToTeam.call(
          project: project,
          user: current_user,
          joining_mode: params.require(:joining_mode),
          capacity: params.require(:capacity),
          roles_needed: params.require(:roles_needed)
        )
        render json: { project: ProjectSerializer.call(converted, viewer: current_user) }
      end

      def convert_to_solo
        project = find_creator_project!
        converted = Projects::ConvertToSolo.call(project: project, user: current_user)
        render json: { project: ProjectSerializer.call(converted, viewer: current_user) }
      end

      def join
        project = find_joinable_project!
        membership = Projects::InstantJoin.call(
          project: project,
          user: current_user,
          participant_role: params.require(:participant_role)
        )
        render json: {
          membership: membership_payload(membership),
          project: ProjectSerializer.call(project.reload, viewer: current_user),
          session: SessionSerializer.new(current_user.reload).as_json
        }, status: :created
      end

      def leave
        project = find_workspace_project!
        membership = Projects::Leave.call(
          project: project,
          user: current_user,
          reason_category: params.require(:reason_category),
          reason_detail: params[:reason_detail]
        )
        render json: {
          membership: membership_payload(membership),
          project: ProjectSerializer.call(project.reload, viewer: current_user)
        }
      end

      def remove_member
        project = find_workspace_project!
        membership = Projects::RemoveMember.call(
          project: project,
          actor: current_user,
          member_user: User.find(params.require(:user_id)),
          reason_category: params.require(:reason_category),
          reason_detail: params[:reason_detail]
        )
        render json: {
          membership: membership_payload(membership),
          project: ProjectSerializer.call(project.reload, viewer: current_user)
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

      def find_visible_or_joinable_project!
        workspace = require_workspace!
        project = visible_projects(workspace).find_by(id: params[:id])
        return project if project

        project = Project.find_by(id: params[:id])
        raise ActiveRecord::RecordNotFound if project.nil?

        if project.workspace.organization_id.present?
          raise ActiveRecord::RecordNotFound unless current_user.member_of_workspace?(project.workspace)
          return project
        end

        # Personal team projects: eligible adults may open joinable projects by direct link.
        if project.team? && project.active? && current_user.adult? && !current_user.pending_onboarding?
          return project
        end

        raise ActiveRecord::RecordNotFound
      end

      def find_joinable_project!
        project = Project.find_by(id: params[:id] || params[:project_id])
        raise ActiveRecord::RecordNotFound if project.nil?

        Projects::JoinEligibility.assert_can_join!(project: project, user: current_user)
        project
      end

      def find_workspace_project!
        workspace = require_workspace!
        project = Project.in_workspace(workspace).find_by(id: params[:id])
        if project.nil?
          # Allow leave/remove/manage on projects the user joined even if active workspace differs.
          project = Project.joins(:memberships).find_by(
            id: params[:id],
            project_memberships: { user_id: current_user.id }
          )
        end
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

      def evaluate_if_overdue!(project)
        return unless project.active? && project.past_final_expiration?

        Projects::Lifecycle::Evaluate.call(project: project)
      end

      def membership_payload(membership)
        {
          id: membership.id,
          project_id: membership.project_id,
          user_id: membership.user_id,
          role: membership.role,
          participant_role: membership.participant_role,
          status: membership.status,
          join_source: membership.join_source
        }
      end
    end
  end
end
