# frozen_string_literal: true

module Ai
  class RunProjectDraftGeneration
    def self.call(generation:)
      new(generation: generation).call
    end

    def initialize(generation:)
      @generation = generation
    end

    def call
      return @generation if @generation.succeeded? || @generation.failed?

      if Ai::Config.nonessential_ai_stopped?
        fail!(code: "ai_unavailable", message: "AI generation is temporarily unavailable", retryable: true)
        return @generation
      end

      @generation.update!(status: AiGeneration::STATUS_RUNNING, started_at: Time.current)

      use_case = Ai::Config.use_case(@generation.use_case)
      schema = JSON.parse(File.read(Rails.root.join(use_case[:schema_path])))
      system_prompt = File.read(Rails.root.join(use_case[:prompt_path]))

      messages = [
        { role: "system", content: system_prompt },
        { role: "user", content: user_message }
      ]

      result = Ai::Provider.complete_structured(
        use_case: @generation.use_case,
        messages: messages,
        schema: schema,
        model: use_case[:model],
        temperature: use_case[:temperature],
        max_tokens: use_case[:max_tokens]
      )

      constraints = @generation.constraints || {}
      normalized = Ai::NormalizeProjectDraftDates.call(
        result.content,
        time_available: constraints["time_available"] || "2 weeks"
      )
      validated = Ai::ValidateProjectDraft.call(normalized)

      @generation.update!(
        status: AiGeneration::STATUS_SUCCEEDED,
        result: validated,
        model: result.model,
        prompt_version: use_case[:prompt_version],
        prompt_tokens: result.prompt_tokens,
        completion_tokens: result.completion_tokens,
        total_tokens: result.total_tokens,
        succeeded_at: Time.current,
        error_code: nil,
        error_message: nil,
        retryable: false
      )
      @generation
    rescue DomainError => e
      fail!(code: e.code, message: e.message, retryable: e.code == "ai_schema_invalid")
      @generation
    rescue Ai::Providers::OpenRouter::Error => e
      fail!(code: "ai_provider_error", message: e.message, retryable: e.retryable)
      @generation
    rescue StandardError => e
      Rails.logger.error({ event: "ai_generation_failed", generation_id: @generation.id, error: e.class.name, message: e.message }.to_json)
      fail!(code: "ai_provider_error", message: "Generation failed", retryable: true)
      @generation
    end

    private

    def user_message
      constraints = @generation.constraints || {}
      today = Date.current.iso8601
      <<~TEXT
        Today (UTC calendar date): #{today}
        All project_end_date and recommended_due_date values MUST be strictly after #{today}.

        Prompt:
        #{@generation.prompt}

        Constraints:
        - skill_level: #{constraints['skill_level']}
        - time_available: #{constraints['time_available']}
        - audience: solo (just me)
        - Set project_end_date approximately #{constraints['time_available'] || '2 weeks'} after today.
      TEXT
    end

    def fail!(code:, message:, retryable:)
      @generation.update!(
        status: AiGeneration::STATUS_FAILED,
        error_code: code,
        error_message: message.to_s.truncate(500),
        retryable: retryable,
        failed_at: Time.current
      )
    end
  end
end
