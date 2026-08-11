# frozen_string_literal: true

module Projects
  module Lifecycle
    class ActionGate
      ACTIONS = [
        :join,
        :create_task,
        :submit,
        :review_decide,
        :leave,
        :remove,
        :assign,
        :update_ends_on
      ].freeze

      def self.assert!(project:, action:)
        new(project: project, action: action).assert!
      end

      def self.lazy_evaluate!(project:)
        project.ensure_lifecycle_current!
      end

      def initialize(project:, action:)
        @project = project
        @action = action.to_sym
      end

      def assert!
        raise DomainError.new("Unknown lifecycle action", code: "validation_error") unless ACTIONS.include?(@action)

        self.class.lazy_evaluate!(project: @project)
        @project.reload if @project.past_final_expiration? || @project.expired?

        unless allowed?
          raise DomainError.new(
            denial_message,
            code: "lifecycle_action_denied"
          )
        end

        true
      end

      def allowed?
        case @action
        when :join
          open_work_phase?
        when :create_task, :assign
          open_work_phase?
        when :submit, :review_decide, :leave, :remove
          finishing_phase?
        when :update_ends_on
          finishing_phase? && !@project.past_final_expiration?
        else
          false
        end
      end

      private

      def open_work_phase?
        return false unless @project.active?

        phase = @project.phase
        phase == Project::PHASE_NORMAL || phase == Project::PHASE_ENDING_SOON
      end

      def finishing_phase?
        return false unless @project.active?

        [ Project::PHASE_NORMAL, Project::PHASE_ENDING_SOON, Project::PHASE_GRACE_PERIOD ].include?(@project.phase)
      end

      def denial_message
        case @action
        when :join
          "Joining is closed for this project phase"
        when :create_task
          "New tasks cannot be created in this project phase"
        when :submit
          "Submissions are not allowed in this project phase"
        when :review_decide
          "Reviews are not allowed in this project phase"
        when :leave
          "Leaving is not allowed in this project phase"
        when :remove
          "Removing members is not allowed in this project phase"
        when :assign
          "Assignments are not allowed in this project phase"
        when :update_ends_on
          "End date cannot be changed in this project phase"
        else
          "Action is not allowed in this project phase"
        end
      end
    end
  end
end
