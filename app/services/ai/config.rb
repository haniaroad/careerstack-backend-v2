# frozen_string_literal: true

module Ai
  module Config
    module_function

    def api_key
      ENV.fetch("OPENROUTER_API_KEY", "")
    end

    def base_url
      ENV.fetch("OPENROUTER_BASE_URL", "https://openrouter.ai/api/v1").delete_suffix("/")
    end

    def configured?
      api_key.present?
    end

    def kill_switch?
      truthy?(ENV.fetch("AI_KILL_SWITCH", "false"))
    end

    def budget_stop?
      truthy?(ENV.fetch("AI_BUDGET_STOP", "false"))
    end

    def nonessential_ai_stopped?
      kill_switch? || budget_stop?
    end

    def registry
      @registry ||= YAML.safe_load_file(
        Rails.root.join("config/ai/registry.yml"),
        aliases: true
      ).fetch("use_cases")
    end

    def use_case(name)
      entry = registry[name.to_s]
      raise DomainError.new("Unknown AI use case", code: "validation_error") if entry.nil?

      entry.with_indifferent_access
    end

    def success_rate_limit_per_day
      Integer(ENV.fetch("AI_SUCCESS_RATE_LIMIT_PER_DAY", "10"))
    end

    def truthy?(value)
      %w[1 true yes on].include?(value.to_s.strip.downcase)
    end
  end
end
