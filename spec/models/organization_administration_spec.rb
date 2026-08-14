# frozen_string_literal: true

require "rails_helper"

RSpec.describe Program do
  let(:organization) { create_organization }

  it "defaults new programs to active when created through fixtures" do
    program = create_program(organization: organization)

    expect(program.status).to eq("active")
  end

  it "rejects an unknown status" do
    program = Program.new(organization: organization, name: "X", status: "published")

    expect(program).not_to be_valid
  end

  it "is empty for delete when it has no enrollments, projects, invitations, or reports" do
    program = create_program(organization: organization, status: Program::STATUS_DRAFT)

    expect(program).to be_empty_for_delete
  end

  it "is not empty for delete when it has a program-scoped report" do
    program = create_program(organization: organization, status: Program::STATUS_DRAFT)
    admin = create_onboarded_adult(email: "report-admin@example.com")
    OrganizationReport.create!(
      organization: organization,
      program: program,
      requested_by: admin,
      period_starts_on: Date.new(2026, 1, 1),
      period_ends_on: Date.new(2026, 3, 31),
      format: OrganizationReport::FORMAT_PDF
    )

    expect(program.reload).not_to be_empty_for_delete
  end

  it "is not empty for delete when it has an invitation" do
    program = create_program(organization: organization, status: Program::STATUS_DRAFT)
    Invitation.issue!(organization: organization, program: program)

    expect(program.reload).not_to be_empty_for_delete
  end
end

RSpec.describe ProgramEnrollment do
  let(:organization) { create_organization }
  let(:user) { create_onboarded_adult(email: "enroll@example.com") }
  let(:program) { create_program(organization: organization) }

  it "enforces uniqueness of membership and program" do
    membership = create_membership(organization: organization, user: user, program: program)

    expect {
      ProgramEnrollment.create!(organization_membership: membership, program: program)
    }.to raise_error(ActiveRecord::RecordInvalid)
  end

  it "rejects a program from another organization" do
    membership = create_membership(organization: organization, user: user)
    other = create_program(organization: create_organization(name: "Other"))

    enrollment = ProgramEnrollment.new(organization_membership: membership, program: other)
    expect(enrollment).not_to be_valid
  end
end

RSpec.describe OrganizationUpgradeRequest do
  let(:organization) { create_organization }
  let(:admin) { create_onboarded_adult(email: "upgrade-admin@example.com") }

  before { create_membership(organization: organization, user: admin, role: OrganizationMembership::ADMIN) }

  it "allows only one open request per organization" do
    OrganizationUpgradeRequest.create!(
      organization: organization,
      requesting_user: admin,
      expected_participants: "40",
      expected_projects_or_cohorts: "2 cohorts",
      timeline: "Fall 2026",
      status: "open"
    )

    expect {
      OrganizationUpgradeRequest.create!(
        organization: organization,
        requesting_user: admin,
        expected_participants: "80",
        expected_projects_or_cohorts: "4 cohorts",
        timeline: "Spring 2027",
        status: "open"
      )
    }.to raise_error(ActiveRecord::RecordNotUnique)
  end
end

RSpec.describe Project do
  it "requires a program for organization projects" do
    user = create_onboarded_adult(email: "org-proj@example.com")
    organization = create_organization
    create_membership(organization: organization, user: user, role: OrganizationMembership::ADMIN)

    project = Project.new(
      workspace: organization.workspace,
      creator: user,
      title: "Org project",
      mode: Project::MODE_SOLO
    )

    expect(project).not_to be_valid
    expect(project.errors[:program]).to be_present
  end

  it "rejects a program on personal projects" do
    user = create_onboarded_adult(email: "personal-proj@example.com")
    organization = create_organization
    program = create_program(organization: organization)

    project = Project.new(
      workspace: user.personal_workspace,
      creator: user,
      title: "Personal",
      mode: Project::MODE_SOLO,
      program: program
    )

    expect(project).not_to be_valid
  end
end

RSpec.describe OrganizationReport do
  let(:organization) { create_organization }
  let(:admin) { create_onboarded_adult(email: "report-model@example.com") }

  it "rejects an unknown format" do
    report = OrganizationReport.new(
      organization: organization,
      requested_by: admin,
      period_starts_on: Date.new(2026, 1, 1),
      period_ends_on: Date.new(2026, 1, 31),
      format: "xlsx"
    )

    expect(report).not_to be_valid
  end

  it "rejects an inverted period" do
    report = OrganizationReport.new(
      organization: organization,
      requested_by: admin,
      period_starts_on: Date.new(2026, 3, 1),
      period_ends_on: Date.new(2026, 1, 1),
      format: OrganizationReport::FORMAT_CSV
    )

    expect(report).not_to be_valid
  end
end

RSpec.describe SelfReportedOutcome do
  let(:organization) { create_organization }
  let(:user) { create_onboarded_adult(email: "outcome-model@example.com") }

  before { create_membership(organization: organization, user: user) }

  it "rejects an unknown outcome type" do
    outcome = SelfReportedOutcome.new(
      user: user,
      organization: organization,
      outcome_type: "lottery",
      occurred_on: Date.new(2026, 4, 1),
      careerstack_contribution: SelfReportedOutcome::CONTRIBUTION_YES
    )

    expect(outcome).not_to be_valid
  end

  it "rejects an unknown contribution value" do
    outcome = SelfReportedOutcome.new(
      user: user,
      organization: organization,
      outcome_type: SelfReportedOutcome::TYPE_JOB,
      occurred_on: Date.new(2026, 4, 1),
      careerstack_contribution: "maybe"
    )

    expect(outcome).not_to be_valid
  end

  it "always labels outcomes as self-reported" do
    outcome = SelfReportedOutcome.create!(
      user: user,
      organization: organization,
      outcome_type: SelfReportedOutcome::TYPE_INTERNSHIP,
      occurred_on: Date.new(2026, 4, 1),
      careerstack_contribution: SelfReportedOutcome::CONTRIBUTION_PARTIALLY,
      reporting_label: "verified"
    )

    expect(outcome.reporting_label).to eq("self_reported")
  end
end

RSpec.describe OrganizationReportAudit do
  let(:organization) { create_organization }
  let(:admin) { create_onboarded_adult(email: "audit-model@example.com") }

  it "requires a generate or download action" do
    report = OrganizationReport.create!(
      organization: organization,
      requested_by: admin,
      period_starts_on: Date.new(2026, 1, 1),
      period_ends_on: Date.new(2026, 1, 31),
      format: OrganizationReport::FORMAT_PDF
    )

    audit = OrganizationReportAudit.new(
      organization: organization,
      organization_report: report,
      actor: admin,
      action: "preview",
      format: report.format,
      occurred_at: Time.current
    )

    expect(audit).not_to be_valid
  end
end

RSpec.describe OrganizationMembership do
  it "lets staff export reports" do
    organization = create_organization
    admin = create_onboarded_adult(email: "export-admin@example.com")
    manager = create_onboarded_adult(email: "export-manager@example.com")
    participant = create_onboarded_adult(email: "export-part@example.com")
    admin_membership = create_membership(organization: organization, user: admin, role: OrganizationMembership::ADMIN)
    manager_membership = create_membership(organization: organization, user: manager, role: OrganizationMembership::MANAGER)
    participant_membership = create_membership(organization: organization, user: participant)

    expect(admin_membership).to be_can_export_reports
    expect(manager_membership).to be_can_export_reports
    expect(participant_membership).not_to be_can_export_reports
  end
end
