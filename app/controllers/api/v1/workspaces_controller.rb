# frozen_string_literal: true

module Api
  module V1
    class WorkspacesController < BaseController
      def index
        render json: { workspaces: current_user.usable_workspaces.map { |w| WorkspaceSerializer.call(w) } }
      end

      # Membership is re-checked server-side on every switch; a workspace id the
      # user does not belong to is never activated (D-8).
      def switch
        workspace = Workspace.find(params.require(:workspace_id))

        unless current_user.member_of_workspace?(workspace)
          return render_forbidden("You do not belong to that workspace")
        end

        current_user.update!(active_workspace_id: workspace.id)
        render json: SessionSerializer.call(current_user.reload)
      end

      def program_filter
        Workspaces::SetProgramFilter.call(
          user: current_user,
          mode: params[:mode],
          program_id: params[:program_id]
        )
        render json: SessionSerializer.call(current_user.reload)
      end
    end
  end
end
