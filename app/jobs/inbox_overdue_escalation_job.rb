# frozen_string_literal: true

class InboxOverdueEscalationJob < ApplicationJob
  queue_as :default

  def perform
    Inbox::EvaluateOverdueAndEscalations.call
  end
end
