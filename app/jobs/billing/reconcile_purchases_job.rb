# frozen_string_literal: true

module Billing
  class ReconcilePurchasesJob < ApplicationJob
    queue_as :default

    def perform
      Billing::ReconcilePurchases.call
    end
  end
end
