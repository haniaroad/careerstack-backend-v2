# frozen_string_literal: true

module Api
  module V1
    class ProjectMessagesController < BaseController
      def index
        project = find_project!
        payload = ProjectMessages::List.call(project: project, actor: current_user)
        render json: payload
      end

      def create
        project = find_project!
        message = ProjectMessages::Create.call(
          project: project,
          actor: current_user,
          body: params.require(:body)
        )
        render json: {
          message: {
            id: message.id,
            project_id: message.project_id,
            author_id: message.author_id,
            author_display_name: current_user.profile&.display_name.presence || current_user.email,
            body: message.body,
            created_at: message.created_at
          }
        }, status: :created
      end

      def mark_read
        project = find_project!
        membership = ProjectMessages::MarkRead.call(project: project, actor: current_user)
        render json: {
          unread: false,
          messages_last_read_at: membership.messages_last_read_at
        }
      end

      private

      def find_project!
        Project.find(params[:project_id])
      end
    end
  end
end
