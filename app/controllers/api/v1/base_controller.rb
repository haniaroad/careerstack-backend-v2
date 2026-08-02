# frozen_string_literal: true

module Api
  module V1
    class BaseController < ApplicationController
      rescue_from DomainError do |error|
        render_error(code: error.code, message: error.message, status: error.status)
      end

      private

      def render_validation_error(message, code: DomainError::DEFAULT_CODE)
        render_error(code: code, message: message, status: :unprocessable_entity)
      end

      def render_forbidden(message, code: "forbidden")
        render_error(code: code, message: message, status: :forbidden)
      end

      # Requires that onboarding is finished before a product action runs, so
      # half-registered accounts cannot create organizations or join orgs.
      def require_completed_onboarding!
        return unless current_user.pending_onboarding?

        raise DomainError.new(
          "Complete onboarding before continuing",
          code: "onboarding_required"
        )
      end
    end
  end
end
