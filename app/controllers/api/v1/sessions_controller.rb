# frozen_string_literal: true

module Api
  module V1
    class SessionsController < BaseController
      def show
        subject = impersonation_session&.target || current_user
        payload = SessionSerializer.call(subject)
        if impersonation_session
          payload[:impersonation] = {
            active: true,
            session_id: impersonation_session.id,
            expires_at: impersonation_session.expires_at,
            display_name: subject.profile&.display_name.presence || subject.email
          }
        end
        render json: payload
      end
    end
  end
end
