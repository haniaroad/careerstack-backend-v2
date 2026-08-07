# frozen_string_literal: true

class AiGenerationSerializer
  def self.call(generation)
    new(generation).as_json
  end

  def initialize(generation)
    @generation = generation
  end

  def as_json
    {
      id: @generation.id,
      use_case: @generation.use_case,
      status: @generation.status,
      client_draft_key: @generation.client_draft_key,
      constraints: @generation.constraints,
      result: @generation.succeeded? ? @generation.result : {},
      project_id: @generation.project_id,
      model: @generation.model,
      prompt_version: @generation.prompt_version,
      prompt_tokens: @generation.prompt_tokens,
      completion_tokens: @generation.completion_tokens,
      total_tokens: @generation.total_tokens,
      error_code: @generation.error_code,
      error_message: @generation.error_message,
      retryable: @generation.retryable,
      started_at: @generation.started_at,
      succeeded_at: @generation.succeeded_at,
      failed_at: @generation.failed_at,
      created_at: @generation.created_at,
      updated_at: @generation.updated_at
    }
  end
end
