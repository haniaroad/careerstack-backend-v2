# frozen_string_literal: true

module Projects
  class UpdateDraft
    def self.call(project:, user:, title: nil, summary: :unchanged, skills: :unchanged)
      new(project: project, user: user, title: title, summary: summary, skills: skills).call
    end

    def initialize(project:, user:, title:, summary:, skills:)
      @project = project
      @user = user
      @title = title
      @summary = summary
      @skills = skills
    end

    def call
      authorize!

      attrs = {}
      attrs[:title] = @title.to_s.strip if @title
      attrs[:summary] = @summary.presence if @summary != :unchanged
      if @skills != :unchanged
        attrs[:skills] = Array(@skills).map { |s| s.to_s.strip }.reject(&:blank?).uniq
      end

      @project.update!(attrs)
      @project
    end

    private

    def authorize!
      raise DomainError.new("Only draft projects can be edited", code: "validation_error") unless @project.draft?
      raise DomainError.new("Only the creator can edit this draft", code: "forbidden", status: :forbidden) unless @project.creator_id == @user.id
    end
  end
end
