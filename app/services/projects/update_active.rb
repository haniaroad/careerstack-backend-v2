# frozen_string_literal: true

module Projects
  # Active-project edits for the creator, or organization staff on that
  # organization's projects. Mode, workspace, program, slug, and creator stay locked.
  class UpdateActive
    LOCKED = %w[mode workspace_id program_id slug creator_id].freeze

    def self.call(project:, user:, params:)
      new(project: project, user: user, params: params).call
    end

    def initialize(project:, user:, params:)
      @project = project
      @user = user
      @params = params
    end

    def call
      authorize!
      unless @project.active?
        raise DomainError.new("Only active projects can be updated this way", code: "validation_error")
      end
      Projects::Lifecycle::ActionGate.assert!(project: @project, action: :update_project)
      reject_locked_fields!
      attrs = editable_attributes
      if attrs.empty? && !param_key?(:ends_on)
        raise DomainError.new("No project fields to update", code: "validation_error")
      end

      ActiveRecord::Base.transaction do
        @project.lock!
        @project.reload
        Projects::Lifecycle::ActionGate.assert!(project: @project, action: :update_project)
        @project.update!(attrs) if attrs.any?
        if param_key?(:ends_on)
          Projects::UpdateEndsOn.call(project: @project, user: @user, ends_on: param(:ends_on))
        end
      end

      @project.reload
    rescue ActiveRecord::RecordInvalid => e
      raise DomainError.new(e.record.errors.full_messages.to_sentence, code: "validation_error")
    end

    private

    def authorize!
      return if Projects::Editor.allowed?(project: @project, user: @user)

      raise DomainError.new("You cannot edit this project", code: "forbidden", status: :forbidden)
    end

    def reject_locked_fields!
      return unless LOCKED.any? { |name| param_key?(name) }

      raise DomainError.new(
        "Mode, workspace, program, slug, and creator cannot be changed on an active project",
        code: "validation_error"
      )
    end

    def editable_attributes
      attrs = {}
      attrs[:title] = title_value if param_key?(:title)
      attrs[:summary] = optional_text(:summary) if param_key?(:summary)
      attrs[:objective] = optional_text(:objective) if param_key?(:objective)
      attrs[:definition_of_done] = optional_text(:definition_of_done) if param_key?(:definition_of_done)
      attrs[:visibility] = visibility_value if param_key?(:visibility)
      apply_team_fields!(attrs)
      attrs
    end

    def apply_team_fields!(attrs)
      joining_keys = %i[joining_mode capacity roles_needed]
      return unless joining_keys.any? { |name| param_key?(name) }

      unless @project.team?
        raise DomainError.new("Joining fields apply only to team projects", code: "validation_error")
      end

      attrs[:joining_mode] = joining_mode_value if param_key?(:joining_mode)
      attrs[:capacity] = capacity_value if param_key?(:capacity)
      attrs[:roles_needed] = roles_value if param_key?(:roles_needed)
    end

    def title_value
      title = param(:title).to_s.strip
      raise DomainError.new("Title is required", code: "validation_error") if title.blank?
      raise DomainError.new("Title is too long", code: "validation_error") if title.length > 120

      title
    end

    def optional_text(name)
      param(name).to_s.strip.presence
    end

    def visibility_value
      visibility = param(:visibility).to_s
      return visibility if Project::VISIBILITIES.include?(visibility)

      raise DomainError.new("Invalid project visibility", code: "validation_error")
    end

    def joining_mode_value
      mode = param(:joining_mode).to_s
      return mode if Project::JOINING_MODES.include?(mode)

      raise DomainError.new("Invalid joining mode", code: "validation_error")
    end

    def capacity_value
      capacity = Integer(param(:capacity))
      unless capacity.between?(1, 5)
        raise DomainError.new("Capacity must be between 1 and 5", code: "validation_error")
      end
      if capacity < @project.active_participant_count
        raise DomainError.new(
          "Capacity cannot be lower than the current participant count",
          code: "validation_error"
        )
      end

      capacity
    rescue ArgumentError, TypeError
      raise DomainError.new("Capacity must be between 1 and 5", code: "validation_error")
    end

    def roles_value
      roles = Array(param(:roles_needed)).map { |role| role.to_s.strip }.reject(&:blank?)
      raise DomainError.new("At least one role is required", code: "validation_error") if roles.empty?

      roles
    end

    def param_key?(name)
      @params.key?(name) || @params.key?(name.to_s)
    end

    def param(name)
      return @params[name] if @params.key?(name)

      @params[name.to_s]
    end
  end
end
