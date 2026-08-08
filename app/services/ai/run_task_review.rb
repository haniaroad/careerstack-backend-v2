# frozen_string_literal: true

require "base64"
require "json"

module Ai
  class RunTaskReview
    MAX_TECHNICAL_RETRIES = 2

    def self.call(review:)
      new(review: review).call
    end

    def initialize(review:)
      @review = review
    end

    def call
      return @review if @review.succeeded? || @review.failed?

      attempt_run
    end

    private

    def attempt_run
      if Ai::Config.nonessential_ai_stopped?
        fail_technical!("ai_unavailable", "AI review is temporarily unavailable")
        return @review.reload
      end

      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      @review.update!(status: AiReview::STATUS_RUNNING, started_at: Time.current)

      extraction = Ai::ExtractSubmissionEvidence.call(submission: @review.task_submission)
      use_case = Ai::Config.use_case("task_review")
      schema = JSON.parse(File.read(Rails.root.join(use_case[:schema_path])))
      prompt_template = File.read(Rails.root.join(use_case[:prompt_path]))

      messages = build_messages(prompt_template, extraction)
      result = Ai::Provider.complete_structured(
        use_case: "task_review",
        messages: messages,
        schema: schema,
        model: use_case[:model],
        temperature: use_case[:temperature],
        max_tokens: use_case[:max_tokens]
      )

      parsed = parse_content(result.content)
      decision = normalize_decision(parsed[:decision])
      raise DomainError.new("Invalid review decision", code: "ai_schema_invalid") if decision.nil?

      feedback = {
        "summary" => parsed[:feedback].to_s,
        "unmet_requirements" => Array(parsed[:unmet_requirements]),
        "next_action" => parsed[:next_action].to_s,
        "decision" => decision
      }

      unsupported = extraction.unsupported_items
      analysis_incomplete = extraction.analysis_incomplete || ActiveModel::Type::Boolean.new.cast(parsed[:analysis_incomplete])
      if parsed[:unsupported_items].present?
        unsupported = (unsupported + Array(parsed[:unsupported_items])).uniq
        analysis_incomplete = true
      end

      elapsed_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round

      @review.update!(
        status: AiReview::STATUS_SUCCEEDED,
        decision: decision,
        feedback: feedback,
        analysis_incomplete: analysis_incomplete,
        unsupported_items: unsupported,
        model: result.model.presence || use_case[:model],
        prompt_version: use_case[:prompt_version],
        prompt_tokens: result.prompt_tokens,
        completion_tokens: result.completion_tokens,
        total_tokens: result.total_tokens,
        counts_as_attempt: true,
        completed_at: Time.current,
        processing_ms: elapsed_ms,
        error_code: nil,
        error_message: nil
      )

      Tasks::ApplyReviewDecision.call(task: @review.task, review: @review)
      @review.reload
    rescue DomainError => e
      handle_failure(e.code, e.message)
    rescue Ai::Providers::OpenRouter::Error => e
      handle_failure("ai_provider_error", e.message)
    rescue StandardError => e
      Rails.logger.warn({ event: "ai_review_failed", error_class: e.class.name, review_id: @review.id }.to_json)
      handle_failure("ai_provider_error", "AI review failed")
    end

    def parse_content(content)
      return content.with_indifferent_access if content.is_a?(Hash)

      JSON.parse(content.to_s).with_indifferent_access
    rescue JSON::ParserError
      raise DomainError.new("Invalid review JSON", code: "ai_schema_invalid")
    end

    def build_messages(prompt_template, extraction)
      text = [
        prompt_template,
        "",
        review_context_block,
        "",
        extraction.text_parts.join("\n\n").presence || "No analyzable text evidence was provided.",
        "",
        "Unsupported items (do not claim these were analyzed): #{extraction.unsupported_items.to_json}"
      ].join("\n")

      # Prefer plain string content for text-only reviews; multimodal array only when images are present.
      user_content =
        if extraction.image_blobs.empty?
          text
        else
          content = [ { type: "text", text: text } ]
          extraction.image_blobs.first(3).each do |blob|
            data = Base64.strict_encode64(blob.download)
            content << {
              type: "image_url",
              image_url: { url: "data:#{blob.content_type};base64,#{data}" }
            }
          end
          content
        end

      [
        { role: "system", content: "You are CareerStack solo-task reviewer. Return only structured JSON matching the schema." },
        { role: "user", content: user_content }
      ]
    end

    def review_context_block
      task = @review.task
      project = task.project
      profile = task.assignee&.profile
      generation = project.ai_generations.succeeded.order(created_at: :desc).first
      constraints = generation&.constraints || {}
      skill_level = constraints["skill_level"].presence

      [
        "Project title: #{project.title}",
        "Project summary: #{project.summary.presence || "n/a"}",
        "Project objective: #{project.objective.presence || "n/a"}",
        "Definition of done: #{project.definition_of_done.presence || "n/a"}",
        "Project skills: #{Array(project.skills).presence&.join(", ") || "n/a"}",
        "Expected duration: #{project.expected_duration.presence || "n/a"}",
        "Project ends on: #{project.ends_on.presence || "n/a"}",
        "Project submission expectations: #{project.submission_expectations.presence || "n/a"}",
        "Participant experience level: #{profile&.experience_level.presence || "n/a"}",
        "Project skill level constraint: #{skill_level || "n/a"}",
        "",
        "Task title: #{task.title}",
        "Acceptance criteria: #{task.acceptance_criteria}",
        "Task submission expectations: #{task.submission_expectations}"
      ].join("\n")
    end

    def normalize_decision(value)
      case value.to_s
      when AiReview::DECISION_APPROVED, "approve", "approved"
        AiReview::DECISION_APPROVED
      when AiReview::DECISION_CORRECTIONS_REQUESTED, "corrections", "corrections_requested", "request_corrections"
        AiReview::DECISION_CORRECTIONS_REQUESTED
      end
    end

    def handle_failure(code, message)
      @review.reload
      retries = @review.technical_retry_count
      if retries < MAX_TECHNICAL_RETRIES
        @review.update!(
          technical_retry_count: retries + 1,
          status: AiReview::STATUS_PENDING,
          error_code: code,
          error_message: message.to_s.truncate(500)
        )
        return attempt_run
      end

      fail_technical!(code, message)
      @review.reload
    end

    def fail_technical!(code, message)
      @review.update!(
        status: AiReview::STATUS_FAILED,
        error_code: code,
        error_message: message.to_s.truncate(500),
        counts_as_attempt: false,
        completed_at: Time.current
      )
    end
  end
end
