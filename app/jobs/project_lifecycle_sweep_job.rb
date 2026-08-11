# frozen_string_literal: true

class ProjectLifecycleSweepJob < ApplicationJob
  queue_as :default

  def perform
    Projects::Lifecycle::Sweep.call
  end
end
