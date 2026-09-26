# frozen_string_literal: true

module Api
  module V1
    class FirstRunTipsController < BaseController
      def show
        render json: {
          tip: FirstRunTips::Present.call(user: current_user, destination: params[:destination])
        }
      end

      def dismiss
        FirstRunTips::Dismiss.call(user: current_user, key: params[:key])
        head :no_content
      end

      def replay
        render json: { restored_keys: FirstRunTips::Replay.call(user: current_user) }
      end
    end
  end
end
