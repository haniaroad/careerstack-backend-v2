# frozen_string_literal: true

module Ai
  class CompletionResult
    attr_reader :content, :model, :prompt_tokens, :completion_tokens, :total_tokens, :raw

    def initialize(content:, model:, prompt_tokens: nil, completion_tokens: nil, total_tokens: nil, raw: nil)
      @content = content
      @model = model
      @prompt_tokens = prompt_tokens
      @completion_tokens = completion_tokens
      @total_tokens = total_tokens
      @raw = raw
    end
  end

  module Provider
    class << self
      def complete_structured(use_case:, messages:, schema:, model:, temperature:, max_tokens:)
        adapter.complete_structured(
          use_case: use_case,
          messages: messages,
          schema: schema,
          model: model,
          temperature: temperature,
          max_tokens: max_tokens
        )
      end

      def adapter
        @adapter || Providers::OpenRouter.new
      end

      def stub!(provider)
        @adapter = provider
      end

      def unstub!
        @adapter = nil
      end
    end
  end
end
