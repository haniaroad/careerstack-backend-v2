# frozen_string_literal: true

module Projects
  # Creators may change visibility on draft or active projects.
  class UpdateVisibility
    def self.call(project:, user:, visibility:)
      new(project: project, user: user, visibility: visibility).call
    end

    def initialize(project:, user:, visibility:)
      @project = project
      @user = user
      @visibility = visibility.to_s
    end

    def call
      raise DomainError.new("Only the creator can change visibility", code: "forbidden", status: :forbidden) unless @project.creator_id == @user.id
      raise DomainError.new("Cancelled or archived projects cannot change visibility", code: "validation_error") if @project.cancelled? || @project.archived?
      unless Project::VISIBILITIES.include?(@visibility)
        raise DomainError.new("Invalid project visibility", code: "validation_error")
      end

      @project.update!(visibility: @visibility)
      @project
    end
  end
end
