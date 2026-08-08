# frozen_string_literal: true

module Projects
  class ConvertToSolo
    def self.call(project:, user:)
      new(project: project, user: user).call
    end

    def initialize(project:, user:)
      @project = project
      @user = user
    end

    def call
      authorize!

      ActiveRecord::Base.transaction do
        @project.lock!
        raise DomainError.new("Only active team projects can convert to solo", code: "validation_error") unless @project.active? && @project.team?

        if @project.non_creator_memberships_exist?
          raise DomainError.new("Cannot convert to solo after a participant has joined", code: "validation_error")
        end

        @project.update!(
          mode: Project::MODE_SOLO,
          joining_mode: nil,
          capacity: nil,
          roles_needed: []
        )
      end

      @project.reload
    end

    private

    def authorize!
      raise DomainError.new("Only the creator can convert this project", code: "forbidden", status: :forbidden) unless @project.creator_id == @user.id
      raise DomainError.new("Not a member of this workspace", code: "forbidden", status: :forbidden) unless @user.member_of_workspace?(@project.workspace)
    end
  end
end
