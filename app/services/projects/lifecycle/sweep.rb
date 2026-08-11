# frozen_string_literal: true

module Projects
  module Lifecycle
    class Sweep
      def self.call
        new.call
      end

      def call
        horizon = Time.find_zone!("UTC").today + Project::ENDING_SOON_DAYS.days

        Project.active.where.not(ends_on: nil).where("ends_on <= ?", horizon).find_each do |project|
          Evaluate.call(project: project)
        rescue StandardError => e
          Rails.logger.warn({
            event: "project_lifecycle_sweep_failed",
            project_id: project.id,
            error_class: e.class.name,
            error_message: e.message
          }.to_json)
        end
      end
    end
  end
end
