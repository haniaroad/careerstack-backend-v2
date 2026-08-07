# frozen_string_literal: true

module Projects
  class CreateDraft
    def self.call(user:, workspace:, title:, summary: nil, skills: [])
      new(user: user, workspace: workspace, title: title, summary: summary, skills: skills).call
    end

    def initialize(user:, workspace:, title:, summary:, skills:)
      @user = user
      @workspace = workspace
      @title = title
      @summary = summary
      @skills = Array(skills).map { |s| s.to_s.strip }.reject(&:blank?).uniq
    end

    def call
      authorize!

      Project.create!(
        workspace: @workspace,
        creator: @user,
        title: @title.to_s.strip,
        summary: @summary.presence,
        skills: @skills,
        mode: Project::MODE_SOLO,
        status: Project::STATUS_DRAFT
      )
    end

    private

    def authorize!
      raise DomainError.new("No active workspace", code: "no_workspace") if @workspace.nil?
      raise DomainError.new("Not a member of this workspace", code: "forbidden", status: :forbidden) unless @user.member_of_workspace?(@workspace)
      raise DomainError.new("Complete onboarding before creating projects", code: "onboarding_required", status: :forbidden) if @user.pending_onboarding?

      if @workspace.personal? && !@user.adult?
        raise DomainError.new("Personal projects require a verified adult account", code: "forbidden", status: :forbidden)
      end
    end
  end
end
