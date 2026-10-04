# frozen_string_literal: true

module Home
  # Hides one Home lifecycle warning for the current user until that phase changes.
  class DismissWarning
    def self.call(user:, project_id:, phase:)
      new(user: user, project_id: project_id, phase: phase).call
    end

    def initialize(user:, project_id:, phase:)
      @user = user
      @project_id = project_id
      @phase = phase.to_s
    end

    def call
      unless HomeWarningDismissal::PHASES.include?(@phase)
        raise DomainError.new("phase must be ending_soon, grace_period, or expired", code: "validation_error")
      end

      project = Project.find_by(id: @project_id)
      raise DomainError.new("Project not found", code: "not_found", status: :not_found) if project.nil?
      unless involved?(project)
        raise DomainError.new("Project not found", code: "not_found", status: :not_found)
      end
      unless project.home_warning_phase == @phase
        raise DomainError.new("That warning is not current for this project", code: "validation_error")
      end

      HomeWarningDismissal.find_or_create_by!(user: @user, project: project, phase: @phase) do |row|
        row.dismissed_at = Time.current
      end
    end

    private

    def involved?(project)
      return true if project.creator_id == @user.id

      project.memberships.exists?(user_id: @user.id)
    end
  end
end
