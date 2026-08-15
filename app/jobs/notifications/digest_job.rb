# frozen_string_literal: true

module Notifications
  class DigestJob < ApplicationJob
    queue_as :mailers

    def perform
      Digest.call
    end
  end
end
