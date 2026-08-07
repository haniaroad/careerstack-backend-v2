# frozen_string_literal: true

module Ai
  class AcceptProjectGeneration
    def self.call(generation:, user:, workspace:)
      new(generation: generation, user: user, workspace: workspace).call
    end

    def initialize(generation:, user:, workspace:)
      @generation = generation
      @user = user
      @workspace = workspace
    end

    def call
      authorize!

      payload = @generation.result
      raise DomainError.new("Generation has no result payload", code: "validation_error") if payload.blank?

      validated = Ai::ValidateProjectDraft.call(payload)

      project = nil
      ActiveRecord::Base.transaction do
        project = @generation.project || Project.create!(
          workspace: @workspace,
          creator: @user,
          title: validated["title"].to_s.strip,
          mode: Project::MODE_SOLO,
          status: Project::STATUS_DRAFT,
          source: Project::SOURCE_AI
        )

        raise DomainError.new("Only draft projects can accept generation", code: "validation_error") unless project.draft?
        raise DomainError.new("Only the creator can accept generation", code: "forbidden", status: :forbidden) unless project.creator_id == @user.id

        if project.ai_generation_succeeded? && @generation.project_id != project.id
          raise DomainError.new(
            "This draft already has a successful AI generation. Edit the draft instead of regenerating.",
            code: "ai_allowance_exhausted"
          )
        end

        project.update!(
          title: validated["title"].to_s.strip,
          summary: validated["summary"].to_s.strip,
          objective: validated["learning_objective"].to_s.strip,
          project_type: validated["project_type"].to_s.strip,
          expected_duration: validated["expected_duration"].to_s.strip,
          ends_on: Date.iso8601(validated["project_end_date"]),
          definition_of_done: validated["definition_of_done"].to_s.strip,
          skills: Array(validated["skills_demonstrated"]).map { |s| s.to_s.strip }.reject(&:blank?).uniq,
          roles_needed: Array(validated["roles_needed"]).map { |s| s.to_s.strip }.reject(&:blank?).uniq,
          proposed_tasks: validated["proposed_tasks"],
          submission_expectations: validated["submission_expectations"].to_s.strip,
          source: Project::SOURCE_AI,
          ai_generation_succeeded_at: project.ai_generation_succeeded_at || Time.current
        )

        @generation.update!(project: project)
      end

      project
    end

    private

    def authorize!
      raise DomainError.new("Generation not found", code: "not_found", status: :not_found) unless @generation.owner?(@user)
      raise DomainError.new("Generation workspace mismatch", code: "forbidden", status: :forbidden) unless @generation.workspace_id == @workspace.id
      raise DomainError.new("Generation has not succeeded yet", code: "validation_error") unless @generation.succeeded?
    end
  end
end
