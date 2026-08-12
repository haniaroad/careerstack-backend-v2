# frozen_string_literal: true

module Api
  module V1
    module Public
      class ProjectsController < BaseController
        skip_before_action :require_authentication

        def show
          project = ::PublicProjects::Resolve.find_public!(params[:slug])
          render json: { project: PublicProjectSerializer.call(project) }
        end
      end
    end
  end
end
