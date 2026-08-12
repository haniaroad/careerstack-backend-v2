# frozen_string_literal: true

require "rails_helper"

RSpec.describe Profiles::SlugGenerator do
  include IdentityFixtures

  it "builds a kebab slug from the display name" do
    expect(described_class.call(display_name: "Derien Stephens")).to eq("derien-stephens")
  end

  it "appends a suffix when the base slug is taken" do
    user = create_onboarded_adult(email: "first@example.com")
    user.profile.update_columns(slug: "alex-morgan")

    generated = described_class.call(display_name: "Alex Morgan")
    expect(generated).to start_with("alex-morgan-")
    expect(generated).not_to eq("alex-morgan")
  end
end

RSpec.describe Profiles::AssignSlug do
  include IdentityFixtures

  it "assigns once and does not regenerate on rename" do
    user = create_onboarded_adult(email: "slug@example.com")
    original = user.profile.slug
    expect(original).to be_present

    user.profile.update!(display_name: "Brand New Name")
    described_class.call(profile: user.profile.reload)
    expect(user.profile.reload.slug).to eq(original)
  end
end

RSpec.describe Profiles::RecordContribution do
  include IdentityFixtures

  it "is idempotent for the same subject and kind" do
    user = create_onboarded_adult(email: "contrib@example.com")
    workspace = user.personal_workspace
    project = Project.create!(
      workspace: workspace,
      creator: user,
      title: "Portfolio Site",
      mode: Project::MODE_SOLO,
      status: Project::STATUS_ACTIVE,
      source: Project::SOURCE_MANUAL,
      ends_on: Date.current + 30
    )
    ProjectMembership.create!(project: project, user: user, role: ProjectMembership::ROLE_CREATOR, status: ProjectMembership::STATUS_ACTIVE)
    task = Task.create!(project: project, title: "Ship it", status: Task::STATUS_PENDING, position: 0, assignee: user)

    first = described_class.call(user: user, kind: ContributionEvent::KIND_TASK_APPROVED, subject: task, project: project)
    second = described_class.call(user: user, kind: ContributionEvent::KIND_TASK_APPROVED, subject: task, project: project)

    expect(first.id).to eq(second.id)
    expect(ContributionEvent.where(user_id: user.id, kind: ContributionEvent::KIND_TASK_APPROVED).count).to eq(1)
  end
end

RSpec.describe Profiles::Visibility do
  include IdentityFixtures

  it "marks independent adults as public_adult" do
    user = create_onboarded_adult(email: "visible@example.com")
    expect(described_class.code_for(user)).to eq(Profiles::Visibility::PUBLIC_ADULT)
  end

  it "restricts suspended users" do
    user = create_onboarded_adult(email: "suspended@example.com")
    user.update!(status: User::SUSPENDED)
    expect(described_class.code_for(user)).to eq(Profiles::Visibility::RESTRICTED)
  end

  it "restricts age-up pending adults" do
    user = create_onboarded_adult(email: "ageup@example.com")
    user.update!(onboarding_path: "organization_invited")
    user.age_visibility_preference.require_visibility_review!
    expect(described_class.code_for(user.reload)).to eq(Profiles::Visibility::RESTRICTED)
  end
end
