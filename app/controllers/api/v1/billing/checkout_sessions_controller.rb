# frozen_string_literal: true

module Api
  module V1
    module Billing
      class CheckoutSessionsController < BaseController
        def create
          result = ::Billing::CreateCheckoutSession.call(user: current_user)
          render json: result, status: :created
        end
      end
    end
  end
end
