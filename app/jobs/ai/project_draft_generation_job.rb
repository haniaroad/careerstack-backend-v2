# frozen_string_literal: true

module Ai
  class ProjectDraftGenerationJob < ApplicationJob
    queue_as :default

    def perform(generation_id)
      generation = AiGeneration.find_by(id: generation_id)
      return if generation.nil?

      Ai::RunProjectDraftGeneration.call(generation: generation)
    end
  end
end
