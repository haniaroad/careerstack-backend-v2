# frozen_string_literal: true

module Projects
  class UpdateDraft
    def self.call(project:, user:, **attrs)
      new(project: project, user: user, attrs: attrs).call
    end

    def initialize(project:, user:, attrs:)
      @project = project
      @user = user
      @attrs = attrs
    end

    def call
      authorize!

      updates = {}
      updates[:title] = @attrs[:title].to_s.strip if @attrs.key?(:title) && !@attrs[:title].nil?
      if @attrs.key?(:summary) && @attrs[:summary] != :unchanged
        updates[:summary] = @attrs[:summary].presence
      end
      if @attrs.key?(:skills) && @attrs[:skills] != :unchanged
        updates[:skills] = Array(@attrs[:skills]).map { |s| s.to_s.strip }.reject(&:blank?).uniq
      end
      %i[objective project_type expected_duration definition_of_done submission_expectations].each do |key|
        next unless @attrs.key?(key) && @attrs[key] != :unchanged

        updates[key] = @attrs[key].presence
      end
      if @attrs.key?(:ends_on) && @attrs[:ends_on] != :unchanged
        updates[:ends_on] = @attrs[:ends_on].present? ? Date.parse(@attrs[:ends_on].to_s) : nil
      end
      if @attrs.key?(:roles_needed) && @attrs[:roles_needed] != :unchanged
        updates[:roles_needed] = Array(@attrs[:roles_needed]).map { |s| s.to_s.strip }.reject(&:blank?).uniq
      end
      if @attrs.key?(:proposed_tasks) && @attrs[:proposed_tasks] != :unchanged
        updates[:proposed_tasks] = Array(@attrs[:proposed_tasks])
      end
      if @attrs.key?(:mode) && @attrs[:mode] != :unchanged
        updates[:mode] = @attrs[:mode].to_s
      end
      if @attrs.key?(:joining_mode) && @attrs[:joining_mode] != :unchanged
        updates[:joining_mode] = @attrs[:joining_mode].presence
      end
      if @attrs.key?(:capacity) && @attrs[:capacity] != :unchanged
        updates[:capacity] = @attrs[:capacity].present? ? @attrs[:capacity].to_i : nil
      end
      if @attrs.key?(:visibility) && @attrs[:visibility] != :unchanged
        visibility = @attrs[:visibility].to_s
        unless Project::VISIBILITIES.include?(visibility)
          raise DomainError.new("Invalid project visibility", code: "validation_error")
        end
        updates[:visibility] = visibility
      end
      if @attrs.key?(:program_id) && @attrs[:program_id] != :unchanged
        updates[:program] = resolve_program_update(@attrs[:program_id])
      end

      mode = updates.fetch(:mode, @project.mode)
      if mode == Project::MODE_SOLO
        updates[:joining_mode] = nil if updates.key?(:joining_mode) || updates.key?(:mode)
        updates[:capacity] = nil if updates.key?(:capacity) || updates.key?(:mode)
        updates[:roles_needed] = [] if updates.key?(:mode)
      end

      @project.update!(updates) if updates.any?
      @project
    end

    private

    def authorize!
      raise DomainError.new("Only draft projects can be edited", code: "validation_error") unless @project.draft?
      raise DomainError.new("Only the creator can edit this draft", code: "forbidden", status: :forbidden) unless @project.creator_id == @user.id
      if @project.workspace.organization?
        Organizations::Access.require_writable!(@project.workspace.organization)
      end
    end

    def resolve_program_update(program_id)
      workspace = @project.workspace
      return nil if workspace.personal?

      raise DomainError.new("program_id is required for organization projects", code: "validation_error") if program_id.blank?

      program = workspace.organization.programs.find(program_id)
      raise DomainError.new("Archived programs cannot receive new projects", code: "validation_error") if program.archived?
      raise DomainError.new("Draft programs cannot receive new projects", code: "validation_error") if program.draft?

      program
    end
  end
end
