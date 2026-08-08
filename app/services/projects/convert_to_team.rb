# frozen_string_literal: true

module Projects
  class ConvertToTeam
    def self.call(project:, user:, joining_mode:, capacity:, roles_needed:)
      new(
        project: project,
        user: user,
        joining_mode: joining_mode,
        capacity: capacity,
        roles_needed: roles_needed
      ).call
    end

    def initialize(project:, user:, joining_mode:, capacity:, roles_needed:)
      @project = project
      @user = user
      @joining_mode = joining_mode.to_s
      @capacity = capacity.to_i
      @roles_needed = Array(roles_needed).map { |s| s.to_s.strip }.reject(&:blank?).uniq
    end

    def call
      authorize!

      ActiveRecord::Base.transaction do
        @project.lock!
        raise DomainError.new("Only active solo projects can convert to team", code: "validation_error") unless @project.active? && @project.solo?
        validate_fields!

        @project.update!(
          mode: Project::MODE_TEAM,
          joining_mode: @joining_mode,
          capacity: @capacity,
          roles_needed: @roles_needed
        )

        # Creators cannot be assignees on team projects; clear solo self-assignment.
        @project.tasks.where(assignee_id: @project.creator_id, status: Task::STATUS_PENDING).find_each do |task|
          task.update!(assignee: nil)
        end

        cancel_in_flight_ai_reviews!
      end

      @project.reload
    end

    private

    def authorize!
      raise DomainError.new("Only the creator can convert this project", code: "forbidden", status: :forbidden) unless @project.creator_id == @user.id
      raise DomainError.new("Not a member of this workspace", code: "forbidden", status: :forbidden) unless @user.member_of_workspace?(@project.workspace)
    end

    def validate_fields!
      unless Project::JOINING_MODES.include?(@joining_mode)
        raise DomainError.new("Joining mode is required", code: "validation_error")
      end
      unless @capacity.between?(1, 5)
        raise DomainError.new("Capacity must be between 1 and 5", code: "validation_error")
      end
      if @roles_needed.empty?
        raise DomainError.new("At least one role is required", code: "validation_error")
      end
    end

    def cancel_in_flight_ai_reviews!
      AiReview.where(task_id: @project.tasks.select(:id), status: AiReview::ACTIVE_STATUSES).find_each do |review|
        review.update!(
          status: AiReview::STATUS_FAILED,
          error_code: "project_converted",
          error_message: "Project converted to team; AI review cancelled"
        )
      end
    end
  end
end
