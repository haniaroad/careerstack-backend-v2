# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Organization reporting", type: :request do
  let(:admin) { create_onboarded_adult(email: "report-admin@example.com") }
  let(:manager) { create_onboarded_adult(email: "report-manager@example.com") }
  let(:participant) { create_onboarded_adult(email: "report-participant@example.com") }
  let(:organization) { create_organization(name: "Bridge Academy") }
  let(:program) { create_program(organization: organization, name: "Fall Cohort") }
  let(:other_org) { create_organization(name: "Other Org") }

  before do
    create_membership(organization: organization, user: admin, role: OrganizationMembership::ADMIN)
    create_membership(organization: organization, user: manager, role: OrganizationMembership::MANAGER)
    create_membership(organization: organization, user: participant, program: program)
    create_membership(organization: other_org, user: admin, role: OrganizationMembership::ADMIN)
  end

  def switch_to!(user, workspace)
    post "/api/v1/workspaces/switch",
         params: { workspace_id: workspace.id },
         headers: headers_for(user),
         as: :json
  end

  def org_headers(user, org = organization)
    switch_to!(user, org.workspace)
    headers_for(user)
  end

  def create_params(overrides = {})
    {
      period_starts_on: "2026-01-01",
      period_ends_on: "2026-03-31",
      format: "pdf",
      aggregate_only: false,
      program_id: program.id
    }.merge(overrides)
  end

  it "lets staff create a snapshot without consuming credits" do
    headers = org_headers(manager)

    expect {
      post "/api/v1/organizations/#{organization.id}/reports",
           params: create_params,
           headers: headers,
           as: :json
    }.not_to change(CreditLedgerEntry, :count)

    expect(response).to have_http_status(:created)
    expect(response.parsed_body.dig("report", "status")).to eq("draft")
    expect(response.parsed_body.dig("report", "format")).to eq("pdf")
  end

  it "lets a manager generate and download an aggregate-only CSV" do
    post "/api/v1/organizations/#{organization.id}/reports",
         params: create_params(format: "csv", aggregate_only: true, program_id: nil),
         headers: org_headers(manager),
         as: :json
    report_id = response.parsed_body.dig("report", "id")

    post "/api/v1/organization_reports/#{report_id}/generate", headers: org_headers(manager), as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig("report", "status")).to eq("ready")

    csv = OrganizationReport.find(report_id).file.download
    expect(csv).to include("metric")
    expect(csv).not_to include(participant.email)
    expect(csv.downcase).not_to include("date_of_birth")
    expect(csv.downcase).not_to include("dob")

    post "/api/v1/organization_reports/#{report_id}/download", headers: org_headers(manager), as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body["url"]).to be_present
    expires = Time.zone.parse(response.parsed_body["expires_at"])
    expect(expires).to be_within(1.minute).of(15.minutes.from_now)
    expect(OrganizationReportAudit.where(action: "download", actor: manager).count).to eq(1)

    blob_path = URI.parse(response.parsed_body["url"]).request_uri
    get blob_path
    follow_redirect! while response.redirect?
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("metric")
    expect(response.body).not_to include(participant.email)
  end

  it "requires confirmation before downloading a named report with minor names" do
    participant.update!(age_status: AgeStatusCalculator::MINOR)
    post "/api/v1/organizations/#{organization.id}/reports",
         params: create_params(format: "csv", aggregate_only: false),
         headers: org_headers(admin),
         as: :json
    report_id = response.parsed_body.dig("report", "id")

    post "/api/v1/organization_reports/#{report_id}/generate", headers: org_headers(admin), as: :json
    expect(response.parsed_body.dig("report", "includes_minor_names")).to be(true)

    post "/api/v1/organization_reports/#{report_id}/download", headers: org_headers(admin), as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body.dig("error", "code")).to eq("minor_names_confirmation_required")

    post "/api/v1/organization_reports/#{report_id}/download",
         params: { confirm_minor_names: true },
         headers: org_headers(admin),
         as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body["url"]).to be_present
  end

  it "rejects a participant and a cross-organization id" do
    post "/api/v1/organizations/#{organization.id}/reports",
         params: create_params,
         headers: org_headers(participant),
         as: :json
    expect(response).to have_http_status(:forbidden)

    post "/api/v1/organizations/#{organization.id}/reports",
         params: create_params,
         headers: org_headers(admin, other_org),
         as: :json
    expect(response).to have_http_status(:forbidden)
  end

  it "rejects a program from another organization" do
    foreign_program = create_program(organization: other_org, name: "Foreign")

    post "/api/v1/organizations/#{organization.id}/reports",
         params: create_params(program_id: foreign_program.id),
         headers: org_headers(admin),
         as: :json

    expect(response).to have_http_status(:not_found)
  end

  it "allows export during offboarding read-only and rejects a disabled workspace" do
    Organizations::StartOffboarding.call(organization: organization)

    expect {
      post "/api/v1/organizations/#{organization.id}/reports",
           params: create_params,
           headers: org_headers(admin),
           as: :json
    }.not_to change(CreditLedgerEntry, :count)
    expect(response).to have_http_status(:created)
    report_id = response.parsed_body.dig("report", "id")

    post "/api/v1/organization_reports/#{report_id}/generate", headers: org_headers(admin), as: :json
    expect(response).to have_http_status(:ok)

    Organizations::Disable.call(organization: organization)
    post "/api/v1/organizations/#{organization.id}/reports",
         params: create_params,
         headers: headers_for(admin),
         as: :json
    expect(response).to have_http_status(:forbidden)
  end

  it "blocks empty-draft delete when a program-scoped report exists" do
    draft = create_program(organization: organization, name: "Empty draft", status: Program::STATUS_DRAFT)
    post "/api/v1/organizations/#{organization.id}/reports",
         params: create_params(program_id: draft.id, format: "csv"),
         headers: org_headers(admin),
         as: :json
    expect(response).to have_http_status(:created)

    delete "/api/v1/programs/#{draft.id}", headers: org_headers(admin)
    expect(response).to have_http_status(:unprocessable_entity)
    expect(Program.exists?(draft.id)).to be(true)
  end

  it "rejects unauthenticated download" do
    post "/api/v1/organizations/#{organization.id}/reports",
         params: create_params(format: "csv", aggregate_only: true),
         headers: org_headers(admin),
         as: :json
    report_id = response.parsed_body.dig("report", "id")
    post "/api/v1/organization_reports/#{report_id}/generate", headers: org_headers(admin), as: :json

    post "/api/v1/organization_reports/#{report_id}/download", as: :json
    expect(response).to have_http_status(:unauthorized)
  end

  it "returns outcome aggregates for staff" do
    SelfReportedOutcome.create!(
      user: participant,
      organization: organization,
      program: program,
      outcome_type: SelfReportedOutcome::TYPE_INTERNSHIP,
      occurred_on: Date.new(2026, 2, 1),
      careerstack_contribution: SelfReportedOutcome::CONTRIBUTION_YES
    )

    get "/api/v1/organizations/#{organization.id}/outcome_aggregates",
        headers: org_headers(admin)
    expect(response).to have_http_status(:ok)
    internships = response.parsed_body["outcomes"].find { |row| row["outcome_type"] == "internship" }
    expect(internships["count"]).to eq(1)
    expect(internships["reporting_label"]).to eq("self_reported")
  end
end
