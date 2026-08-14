# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Self-reported outcomes", type: :request do
  let(:participant) { create_onboarded_adult(email: "outcome-part@example.com") }
  let(:admin) { create_onboarded_adult(email: "outcome-admin@example.com") }
  let(:personal_only) { create_onboarded_adult(email: "outcome-personal@example.com") }
  let(:organization) { create_organization(name: "Outcome Org") }
  let(:program) { create_program(organization: organization) }

  before do
    create_membership(organization: organization, user: participant, program: program)
    create_membership(organization: organization, user: admin, role: OrganizationMembership::ADMIN)
  end

  def switch_to!(user, workspace)
    post "/api/v1/workspaces/switch",
         params: { workspace_id: workspace.id },
         headers: headers_for(user),
         as: :json
  end

  it "lets an organization participant record a required outcome" do
    switch_to!(participant, organization.workspace)

    post "/api/v1/outcomes",
         params: {
           outcome_type: "job",
           month: 4,
           year: 2026,
           careerstack_contribution: "yes",
           user_id: admin.id
         },
         headers: headers_for(participant),
         as: :json

    expect(response).to have_http_status(:created)
    expect(response.parsed_body.dig("outcome", "reporting_label")).to eq("self_reported")
    expect(response.parsed_body.dig("outcome", "outcome_type")).to eq("job")
    expect(SelfReportedOutcome.find(response.parsed_body.dig("outcome", "id")).user_id).to eq(participant.id)
  end

  it "rejects missing month and year" do
    switch_to!(participant, organization.workspace)

    post "/api/v1/outcomes",
         params: { outcome_type: "job", careerstack_contribution: "yes" },
         headers: headers_for(participant),
         as: :json

    expect(response).to have_http_status(:unprocessable_entity)
    expect(SelfReportedOutcome.count).to eq(0)
  end

  it "rejects a personal-only user" do
    post "/api/v1/outcomes",
         params: { outcome_type: "job", month: 4, year: 2026, careerstack_contribution: "yes" },
         headers: headers_for(personal_only),
         as: :json

    expect(response).to have_http_status(:forbidden)
  end

  it "does not include outcomes on own or public profile DTOs" do
    switch_to!(participant, organization.workspace)
    post "/api/v1/outcomes",
         params: { outcome_type: "internship", month: 2, year: 2026, careerstack_contribution: "partially" },
         headers: headers_for(participant),
         as: :json
    expect(response).to have_http_status(:created)

    get "/api/v1/profiles/me", headers: headers_for(participant)
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.keys).not_to include("outcomes")
    expect(response.parsed_body.to_s).not_to include("internship")

    slug = participant.profile.slug
    get "/api/v1/profiles/#{slug}", headers: headers_for(admin)
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.keys).not_to include("outcomes")

    get "/api/v1/public/profiles/#{slug}"
    expect(response.parsed_body.keys).not_to include("outcomes")
  end
end
