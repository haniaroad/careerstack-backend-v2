# frozen_string_literal: true

class ProjectSerializer
  def self.call(project, include_tasks: true, viewer: nil)
    new(project, include_tasks: include_tasks, viewer: viewer).as_json
  end

  def initialize(project, include_tasks: true, viewer: nil)
    @project = project
    @include_tasks = include_tasks
    @viewer = viewer
  end

  def as_json
    payload = {
      id: @project.id,
      title: @project.title,
      summary: @project.summary,
      skills: @project.skills,
      mode: @project.mode,
      status: @project.status,
      phase: @project.phase,
      source: @project.source,
      joining_mode: @project.joining_mode,
      capacity: @project.capacity,
      participant_count: @project.team? ? @project.active_participant_count : nil,
      seats_remaining: @project.team? ? @project.seats_remaining : nil,
      recruitment_state: @project.recruitment_state,
      objective: @project.objective,
      project_type: @project.project_type,
      expected_duration: @project.expected_duration,
      ends_on: @project.ends_on,
      final_expires_at: @project.final_expires_at,
      definition_of_done: @project.definition_of_done,
      roles_needed: @project.roles_needed,
      proposed_tasks: @project.proposed_tasks,
      submission_expectations: @project.submission_expectations,
      ai_generation_succeeded_at: @project.ai_generation_succeeded_at,
      workspace_id: @project.workspace_id,
      creator_id: @project.creator_id,
      confirmed_at: @project.confirmed_at,
      completed_at: @project.completed_at,
      expired_at: @project.expired_at,
      cancelled_at: @project.cancelled_at,
      created_at: @project.created_at,
      updated_at: @project.updated_at,
      memberships: active_memberships.map { |m| membership_json(m) }
    }
    payload[:tasks] = @project.tasks.order(:position).map { |t| TaskSerializer.call(t) } if @include_tasks

    if @viewer && creator_viewer?
      payload[:pending_applications] = @project.applications.pending.order(created_at: :desc).map { |a| application_json(a) }
      payload[:pending_invitations] = @project.invitations.pending.order(created_at: :desc).map { |i| invitation_json(i) }
    end

    if @viewer && !member_viewer? && @project.team?
      payload[:viewer_can_join] = @project.joinable?
    end

    payload
  end

  private

  def active_memberships
    @project.memberships.active.includes(user: :profile).order(:created_at)
  end

  def creator_viewer?
    @viewer && @project.creator_id == @viewer.id
  end

  def member_viewer?
    return false unless @viewer

    @project.memberships.active.exists?(user_id: @viewer.id)
  end

  def membership_json(membership)
    {
      id: membership.id,
      user_id: membership.user_id,
      role: membership.role,
      participant_role: membership.participant_role,
      status: membership.status,
      join_source: membership.join_source,
      display_name: membership.user.profile&.display_name.presence || membership.user.email
    }
  end

  def application_json(application)
    {
      id: application.id,
      applicant_id: application.applicant_id,
      requested_role: application.requested_role,
      motivation: application.motivation,
      availability_confirmed: application.availability_confirmed,
      skills: application.skills,
      portfolio_url: application.portfolio_url,
      github_url: application.github_url,
      resume_url: application.resume_url,
      status: application.status,
      created_at: application.created_at
    }
  end

  def invitation_json(invitation)
    {
      id: invitation.id,
      invitee_id: invitation.invitee_id,
      requested_role: invitation.requested_role,
      status: invitation.status,
      created_at: invitation.created_at
    }
  end
end
