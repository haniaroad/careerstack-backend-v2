# frozen_string_literal: true

module Api
  module V1
    class OutcomesController < BaseController
      def index
        outcomes = current_user.self_reported_outcomes.order(occurred_on: :desc, created_at: :desc)
        render json: { outcomes: outcomes.map { |outcome| SelfReportedOutcomeSerializer.call(outcome) } }
      end

      def create
        outcome = Outcomes::Create.call(actor: current_user, params: outcome_params)
        render json: { outcome: SelfReportedOutcomeSerializer.call(outcome) }, status: :created
      end

      private

      def outcome_params
        params.permit(
          :outcome_type, :month, :year, :careerstack_contribution,
          :institution, :title, :note, :program_id, :project_id, :user_id
        )
      end
    end
  end
end
