# frozen_string_literal: true

module Projects
  class SubmitApplication
    def self.call(project:, user:, requested_role:, motivation:, availability_confirmed:,
                  skills: [], portfolio_url: nil, github_url: nil, resume_url: nil)
      new(
        project: project,
        user: user,
        requested_role: requested_role,
        motivation: motivation,
        availability_confirmed: availability_confirmed,
        skills: skills,
        portfolio_url: portfolio_url,
        github_url: github_url,
        resume_url: resume_url
      ).call
    end

    def initialize(project:, user:, requested_role:, motivation:, availability_confirmed:, skills:, portfolio_url:, github_url:, resume_url:)
      @project = project
      @user = user
      @requested_role = requested_role
      @motivation = motivation
      @availability_confirmed = availability_confirmed
      @skills = skills
      @portfolio_url = portfolio_url
      @github_url = github_url
      @resume_url = resume_url
    end

    def call
      Projects::JoinEligibility.assert_can_join!(project: @project, user: @user)
      Projects::Lifecycle::ActionGate.assert!(project: @project, action: :join)
      unless @project.joining_mode == Project::JOINING_APPLICATION
        raise DomainError.new("This project does not accept applications", code: "validation_error")
      end
      raise DomainError.new("Project is not accepting applications", code: "validation_error") unless @project.joinable?
      raise ActiveParticipationConflict if ProjectMembership.active_participation?(@user)
      raise DomainError.new("Creator cannot apply", code: "validation_error") if @user.id == @project.creator_id

      if @project.applications.pending.exists?(applicant_id: @user.id)
        raise DomainError.new("You already have a pending application", code: "validation_error")
      end

      unless ActiveModel::Type::Boolean.new.cast(@availability_confirmed)
        raise DomainError.new("Availability confirmation is required", code: "validation_error")
      end

      ProjectApplication.create!(
        project: @project,
        applicant: @user,
        requested_role: @requested_role.to_s.strip,
        motivation: @motivation.to_s.strip,
        availability_confirmed: true,
        skills: Array(@skills).map { |s| s.to_s.strip }.reject(&:blank?).uniq,
        portfolio_url: @portfolio_url.presence,
        github_url: @github_url.presence,
        resume_url: @resume_url.presence,
        status: ProjectApplication::STATUS_PENDING
      ).tap do |application|
        Notifications::Hook.emit(
          event_key: "application_received",
          actor: @user,
          recipients: [ @project.creator ],
          source: application,
          project: @project,
          payload: Notifications::Hook.project_payload(@project)
        )
      end
    end
  end
end
