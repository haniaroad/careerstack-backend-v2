# frozen_string_literal: true

module Api
  module V1
    # Age-up visibility review. A user whose derived status became adult stays
    # private until they explicitly confirm, and the choice is reversible.
    class AgeVisibilitiesController < BaseController
      DECISIONS = %w[confirm reverse].freeze

      def update
        unless current_user.adult?
          return render_forbidden("Only adults can change public visibility")
        end

        decision = params.require(:decision).to_s
        unless DECISIONS.include?(decision)
          return render_validation_error("decision must be one of #{DECISIONS.join(', ')}")
        end

        preference = current_user.age_visibility_preference || current_user.create_age_visibility_preference!
        decision == "confirm" ? preference.confirm_public_identity! : preference.reverse_public_identity!

        render json: SessionSerializer.call(current_user.reload)
      end
    end
  end
end
