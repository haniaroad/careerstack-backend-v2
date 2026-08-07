# frozen_string_literal: true

require "net/http"
require "json"
require "uri"

module Ai
  module Providers
    class OpenRouter
      class Error < StandardError
        attr_reader :retryable

        def initialize(message, retryable: true)
          super(message)
          @retryable = retryable
        end
      end

      def complete_structured(use_case:, messages:, schema:, model:, temperature:, max_tokens:)
        unless Ai::Config.configured?
          raise DomainError.new(
            "AI provider is not configured",
            code: "ai_not_configured",
            status: :service_unavailable
          )
        end

        body = {
          model: model,
          temperature: temperature,
          max_tokens: max_tokens,
          messages: messages,
          response_format: {
            type: "json_schema",
            json_schema: {
              name: use_case.to_s,
              strict: true,
              schema: schema
            }
          }
        }

        response = post_json("/chat/completions", body)
        choice = Array(response["choices"]).first
        content = choice&.dig("message", "content")
        raise Error.new("Empty completion from provider", retryable: true) if content.blank?

        usage = response["usage"] || {}
        Ai::CompletionResult.new(
          content: content,
          model: response["model"] || model,
          prompt_tokens: usage["prompt_tokens"],
          completion_tokens: usage["completion_tokens"],
          total_tokens: usage["total_tokens"],
          raw: { id: response["id"], use_case: use_case }
        )
      end

      private

      def post_json(path, body)
        uri = URI.parse("#{Ai::Config.base_url}#{path}")
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == "https"
        http.open_timeout = 10
        http.read_timeout = 90

        request = Net::HTTP::Post.new(uri.request_uri)
        request["Authorization"] = "Bearer #{Ai::Config.api_key}"
        request["Content-Type"] = "application/json"
        request["HTTP-Referer"] = "https://careerstack.co"
        request["X-Title"] = "CareerStack"
        request.body = JSON.generate(body)

        response = http.request(request)
        parsed = parse_body(response.body)

        unless response.is_a?(Net::HTTPSuccess)
          message = parsed.dig("error", "message") || "OpenRouter request failed (#{response.code})"
          retryable = response.code.to_i >= 500 || response.code.to_i == 429
          raise Error.new(message, retryable: retryable)
        end

        parsed
      rescue JSON::ParserError
        raise Error.new("Invalid JSON from OpenRouter", retryable: true)
      rescue Timeout::Error, Errno::ECONNREFUSED, Errno::ECONNRESET, SocketError => e
        raise Error.new("OpenRouter network error: #{e.class}", retryable: true)
      end

      def parse_body(body)
        return {} if body.blank?

        JSON.parse(body)
      end
    end
  end
end
