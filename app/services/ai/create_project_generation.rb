# frozen_string_literal: true

require "digest"

module Ai
  class CreateProjectGeneration
    def self.call(user:, workspace:, prompt:, constraints: {}, client_draft_key: nil, project: nil)
      new(
        user: user,
        workspace: workspace,
        prompt: prompt,
        constraints: constraints,
        client_draft_key: client_draft_key,
        project: project
      ).call
    end

    def initialize(user:, workspace:, prompt:, constraints:, client_draft_key:, project:)
      @user = user
      @workspace = workspace
      @prompt = prompt.to_s.strip
      @constraints = normalize_constraints(constraints)
      @client_draft_key = client_draft_key.presence
      @project = project
    end

    def call
      authorize!
      enforce_runtime_controls!
      enforce_rate_limit!
      enforce_allowance!

      generation = AiGeneration.create!(
        user: @user,
        workspace: @workspace,
        project: @project,
        use_case: AiGeneration::USE_CASE_PROJECT_DRAFT,
        status: AiGeneration::STATUS_PENDING,
        client_draft_key: @client_draft_key,
        prompt: @prompt,
        prompt_digest: Digest::SHA256.hexdigest(@prompt),
        constraints: @constraints,
        prompt_version: Ai::Config.use_case(AiGeneration::USE_CASE_PROJECT_DRAFT)[:prompt_version]
      )

      generation
    end

    private

    def authorize!
      raise DomainError.new("No active workspace", code: "no_workspace") if @workspace.nil?
      raise DomainError.new("Not a member of this workspace", code: "forbidden", status: :forbidden) unless @user.member_of_workspace?(@workspace)
      raise DomainError.new("Complete onboarding before creating projects", code: "onboarding_required", status: :forbidden) if @user.pending_onboarding?

      if @workspace.personal? && !@user.adult?
        raise DomainError.new("Personal projects require a verified adult account", code: "forbidden", status: :forbidden)
      end

      if @project
        raise DomainError.new("Project not in active workspace", code: "forbidden", status: :forbidden) unless @project.workspace_id == @workspace.id
        raise DomainError.new("Only the creator can generate for this draft", code: "forbidden", status: :forbidden) unless @project.creator_id == @user.id
        raise DomainError.new("Only draft projects can receive generation", code: "validation_error") unless @project.draft?
      end

      raise DomainError.new("Prompt is required", code: "validation_error") if @prompt.blank?
      raise DomainError.new("Prompt is too long", code: "validation_error") if @prompt.length > 4000
    end

    def enforce_runtime_controls!
      if Ai::Config.nonessential_ai_stopped?
        raise DomainError.new(
          "AI generation is temporarily unavailable",
          code: "ai_unavailable",
          status: :service_unavailable
        )
      end

      unless Ai::Config.configured?
        raise DomainError.new(
          "AI provider is not configured",
          code: "ai_not_configured",
          status: :service_unavailable
        )
      end
    end

    def enforce_rate_limit!
      window_start = 24.hours.ago
      count = AiGeneration.for_user(@user).succeeded.where("succeeded_at >= ?", window_start).count
      return if count < Ai::Config.success_rate_limit_per_day

      raise DomainError.new(
        "AI generation rate limit exceeded. Try again later.",
        code: "ai_rate_limited",
        status: :too_many_requests
      )
    end

    def enforce_allowance!
      if @project
        return unless @project.ai_generation_succeeded?

        raise DomainError.new(
          "This draft already has a successful AI generation. Edit the draft instead of regenerating.",
          code: "ai_allowance_exhausted",
          status: :unprocessable_entity
        )
      end

      return if @client_draft_key.blank?

      exists = AiGeneration.for_user(@user).succeeded.exists?(client_draft_key: @client_draft_key)
      return unless exists

      raise DomainError.new(
        "This draft already has a successful AI generation. Edit the draft instead of regenerating.",
        code: "ai_allowance_exhausted",
        status: :unprocessable_entity
      )
    end

    def normalize_constraints(raw)
      raw = raw.respond_to?(:to_unsafe_h) ? raw.to_unsafe_h : raw
      hash = (raw || {}).to_h.stringify_keys
      {
        "skill_level" => hash["skill_level"].presence || "beginner",
        "time_available" => hash["time_available"].presence || "2 weeks",
        "audience" => "solo"
      }
    end
  end
end
