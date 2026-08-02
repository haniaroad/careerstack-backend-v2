# frozen_string_literal: true

module Api
  module V1
    class SessionsController < BaseController
      def show
        render json: SessionSerializer.call(current_user)
      end
    end
  end
end
