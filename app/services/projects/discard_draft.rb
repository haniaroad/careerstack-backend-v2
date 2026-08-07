# frozen_string_literal: true

module Projects
  class DiscardDraft
    def self.call(project:, user:)
      new(project: project, user: user).call
    end

    def initialize(project:, user:)
      @project = project
      @user = user
    end

    def call
      raise DomainError.new("Only draft projects can be discarded", code: "validation_error") unless @project.draft?
      raise DomainError.new("Only the creator can discard this draft", code: "forbidden", status: :forbidden) unless @project.creator_id == @user.id

      @project.destroy!
      true
    end
  end
end
