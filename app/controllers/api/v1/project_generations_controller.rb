# frozen_string_literal: true

module Api
  module V1
    class ProjectGenerationsController < BaseController
      def create
        workspace = require_workspace!
        project = optional_project!(workspace)

        generation = Ai::CreateProjectGeneration.call(
          user: current_user,
          workspace: workspace,
          prompt: params.require(:prompt),
          constraints: params[:constraints] || {},
          client_draft_key: params[:client_draft_key],
          project: project
        )

        if Rails.env.test? || inline_ai_jobs?
          Ai::RunProjectDraftGeneration.call(generation: generation.reload)
        else
          Ai::ProjectDraftGenerationJob.perform_later(generation.id)
        end

        render json: { generation: AiGenerationSerializer.call(generation.reload) }, status: :accepted
      end

      def show
        generation = find_owned_generation!
        render json: { generation: AiGenerationSerializer.call(generation) }
      end

      def accept
        workspace = require_workspace!
        generation = find_owned_generation!
        project = Ai::AcceptProjectGeneration.call(
          generation: generation,
          user: current_user,
          workspace: workspace,
          program_id: params[:program_id]
        )
        render json: {
          project: ProjectSerializer.call(project),
          generation: AiGenerationSerializer.call(generation.reload)
        }
      end

      private

      def require_workspace!
        workspace = current_user.resolved_active_workspace
        raise DomainError.new("No active workspace", code: "no_workspace") if workspace.nil?

        workspace
      end

      def optional_project!(workspace)
        return nil if params[:project_id].blank?

        project = Project.in_workspace(workspace).find_by(id: params[:project_id], creator_id: current_user.id)
        raise ActiveRecord::RecordNotFound if project.nil?

        project
      end

      def find_owned_generation!
        generation = AiGeneration.find_by(id: params[:id], user_id: current_user.id)
        raise ActiveRecord::RecordNotFound if generation.nil?

        generation
      end

      def inline_ai_jobs?
        ENV["AI_INLINE_JOBS"].to_s == "true"
      end
    end
  end
end
