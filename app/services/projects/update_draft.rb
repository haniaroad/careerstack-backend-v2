# frozen_string_literal: true

module Projects
  class UpdateDraft
    EDITABLE = %i[
      title summary skills objective project_type expected_duration ends_on
      definition_of_done roles_needed proposed_tasks submission_expectations
    ].freeze

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

      @project.update!(updates) if updates.any?
      @project
    end

    private

    def authorize!
      raise DomainError.new("Only draft projects can be edited", code: "validation_error") unless @project.draft?
      raise DomainError.new("Only the creator can edit this draft", code: "forbidden", status: :forbidden) unless @project.creator_id == @user.id
    end
  end
end
