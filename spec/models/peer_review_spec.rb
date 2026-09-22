# frozen_string_literal: true

require "rails_helper"

RSpec.describe PeerReview do
  def team_ctx
    creator = create_onboarded_adult(email: "pr-model-c-#{SecureRandom.hex(3)}@example.com")
    participant = create_onboarded_adult(email: "pr-model-p-#{SecureRandom.hex(3)}@example.com")
    project = Projects::CreateDraft.call(
      user: creator,
      workspace: creator.personal_workspace,
      title: "Model team",
      mode: Project::MODE_TEAM,
      joining_mode: Project::JOINING_INSTANT,
      capacity: 3,
      roles_needed: [ "Designer" ]
    )
    project.update!(status: Project::STATUS_COMPLETED, completed_at: Time.current, ends_on: Date.current + 14)
    ProjectMembership.create!(project: project, user: creator, role: ProjectMembership::ROLE_CREATOR, status: ProjectMembership::STATUS_ACTIVE)
    ProjectMembership.create!(
      project: project,
      user: participant,
      role: ProjectMembership::ROLE_PARTICIPANT,
      status: ProjectMembership::STATUS_ACTIVE,
      participant_role: "Designer",
      join_source: ProjectMembership::JOIN_SOURCE_INSTANT
    )
    { creator: creator, participant: participant, project: project }
  end

  it "rejects a self-review" do
    ctx = team_ctx
    review = PeerReview.new(
      project: ctx[:project],
      reviewer: ctx[:creator],
      reviewee: ctx[:creator],
      status: PeerReview::STATUS_AVAILABLE
    )
    expect(review).not_to be_valid
    expect(review.errors[:reviewee_id]).to be_present
  end

  it "enforces unique reviewer/reviewee pairs per project" do
    ctx = team_ctx
    PeerReview.create!(
      project: ctx[:project],
      reviewer: ctx[:creator],
      reviewee: ctx[:participant],
      status: PeerReview::STATUS_AVAILABLE
    )
    duplicate = PeerReview.new(
      project: ctx[:project],
      reviewer: ctx[:creator],
      reviewee: ctx[:participant],
      status: PeerReview::STATUS_AVAILABLE
    )
    expect(duplicate).not_to be_valid
  end

  it "requires rating and comment only when completed" do
    ctx = team_ctx
    available = PeerReview.create!(
      project: ctx[:project],
      reviewer: ctx[:creator],
      reviewee: ctx[:participant],
      status: PeerReview::STATUS_AVAILABLE
    )
    expect(available).to be_valid

    available.status = PeerReview::STATUS_COMPLETED
    expect(available).not_to be_valid
    expect(available.errors[:rating]).to be_present
    expect(available.errors[:comment]).to be_present

    available.rating = 4
    available.comment = "Clear work"
    available.submitted_at = Time.current
    expect(available).to be_valid
  end

  it "omits hidden reviews from public received lists" do
    ctx = team_ctx
    visible = PeerReview.create!(
      project: ctx[:project],
      reviewer: ctx[:creator],
      reviewee: ctx[:participant],
      status: PeerReview::STATUS_COMPLETED,
      rating: 5,
      comment: "Visible",
      submitted_at: Time.current
    )
    hidden = PeerReview.create!(
      project: ctx[:project],
      reviewer: ctx[:participant],
      reviewee: ctx[:creator],
      status: PeerReview::STATUS_COMPLETED,
      rating: 3,
      comment: "Hidden",
      submitted_at: Time.current,
      hidden_at: Time.current
    )

    expect(PeerReview.received_by(ctx[:participant])).to contain_exactly(visible)
    expect(PeerReview.received_by(ctx[:creator])).to be_empty
    expect(hidden).to be_hidden
  end
end

RSpec.describe PeerReviewReport do
  it "allows one open report per reviewer pair" do
    creator = create_onboarded_adult(email: "pr-rep-c-#{SecureRandom.hex(3)}@example.com")
    participant = create_onboarded_adult(email: "pr-rep-p-#{SecureRandom.hex(3)}@example.com")
    project = Projects::CreateDraft.call(
      user: creator,
      workspace: creator.personal_workspace,
      title: "Report team",
      mode: Project::MODE_TEAM,
      joining_mode: Project::JOINING_INSTANT,
      capacity: 2,
      roles_needed: [ "Designer" ]
    )
    project.update!(status: Project::STATUS_COMPLETED, completed_at: Time.current, ends_on: Date.current + 14)
    review = PeerReview.create!(
      project: project,
      reviewer: creator,
      reviewee: participant,
      status: PeerReview::STATUS_COMPLETED,
      rating: 4,
      comment: "Solid",
      submitted_at: Time.current
    )

    PeerReviewReport.create!(
      peer_review: review,
      reporter: participant,
      report_type: "inappropriate",
      reason_category: "other",
      status: PeerReviewReport::STATUS_OPEN
    )
    duplicate = PeerReviewReport.new(
      peer_review: review,
      reporter: participant,
      report_type: "harassment",
      reason_category: "harassment",
      status: PeerReviewReport::STATUS_OPEN
    )
    expect(duplicate).not_to be_valid
  end
end
