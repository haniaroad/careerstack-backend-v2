# frozen_string_literal: true

require "rails_helper"

RSpec.describe Project, "lifecycle phase helpers" do
  def build_active_project!(ends_on:)
    user = create_onboarded_adult(email: "phase-#{SecureRandom.hex(3)}@example.com")
    project = Projects::CreateDraft.call(user: user, workspace: user.personal_workspace, title: "Phase project")
    project.update!(ends_on: ends_on)
    Projects::Confirm.call(project: project, user: user)
    project.reload
  end

  it "is normal more than seven days before ends_on" do
    project = build_active_project!(ends_on: Date.current + 8)
    expect(project.phase).to eq(Project::PHASE_NORMAL)
    expect(project.ending_soon?).to eq(false)
  end

  it "is ending_soon from T-7 through ends_on" do
    project = build_active_project!(ends_on: Date.current + 7)
    expect(project.phase).to eq(Project::PHASE_ENDING_SOON)

    project.update!(ends_on: Date.current)
    expect(project.phase).to eq(Project::PHASE_ENDING_SOON)
    expect(project.ending_soon?).to eq(true)
  end

  it "is grace_period after ends_on through ends_on + 7" do
    project = build_active_project!(ends_on: Date.current + 14)
    project.update_columns(ends_on: Date.current - 1)
    expect(project.reload.phase).to eq(Project::PHASE_GRACE_PERIOD)
    expect(project.grace_period?).to eq(true)
    expect(project.past_final_expiration?).to eq(false)

    project.update_columns(ends_on: Date.current - 7)
    expect(project.reload.phase).to eq(Project::PHASE_GRACE_PERIOD)
    expect(project.past_final_expiration?).to eq(false)
  end

  it "is past final expiration after ends_on + 7 while still active" do
    project = build_active_project!(ends_on: Date.current + 14)
    project.update_columns(ends_on: Date.current - 8)
    expect(project.reload.past_final_expiration?).to eq(true)
    expect(project.phase).to eq(Project::PHASE_GRACE_PERIOD)
    expect(project.final_expires_at).to eq((project.ends_on + 7.days).in_time_zone("UTC").end_of_day)
  end

  it "is read_only when completed, expired, or cancelled" do
    project = build_active_project!(ends_on: Date.current + 14)
    project.update!(status: Project::STATUS_COMPLETED, completed_at: Time.current)
    expect(project.phase).to eq(Project::PHASE_READ_ONLY)
    expect(project.read_only_phase?).to eq(true)

    project.update!(status: Project::STATUS_EXPIRED, expired_at: Time.current, completed_at: nil)
    expect(project.phase).to eq(Project::PHASE_READ_ONLY)

    project.update!(status: Project::STATUS_CANCELLED, cancelled_at: Time.current, expired_at: nil)
    expect(project.phase).to eq(Project::PHASE_READ_ONLY)
  end

  it "closes recruitment during grace" do
    user = create_onboarded_adult(email: "recruit-#{SecureRandom.hex(3)}@example.com")
    project = Projects::CreateDraft.call(
      user: user,
      workspace: user.personal_workspace,
      title: "Team",
      mode: Project::MODE_TEAM,
      joining_mode: Project::JOINING_INSTANT,
      capacity: 3,
      roles_needed: [ "Designer" ]
    )
    project.update!(ends_on: Date.current + 14)
    Projects::Confirm.call(project: project, user: user)
    project.update_columns(ends_on: Date.current - 1)

    expect(project.reload.recruitment_state).to eq(Project::RECRUITMENT_CLOSED)
    expect(project.joinable?).to eq(false)
  end
end
