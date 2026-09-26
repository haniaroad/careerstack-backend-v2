# frozen_string_literal: true

require "rails_helper"

RSpec.describe "First-run tips API", type: :request do
  def switch_to!(user, workspace)
    post "/api/v1/workspaces/switch",
         params: { workspace_id: workspace.id },
         headers: headers_for(user),
         as: :json
    expect(response).to have_http_status(:ok)
  end

  it "defines exactly the four destination keys under the lifetime ceiling" do
    expect(FirstRunTips::Catalog::KEYS).to eq(%w[home my_work inbox profile])
    expect(FirstRunTips::Catalog::KEYS.size).to be <= FirstRunTips::Catalog::MAX_KEYS
  end

  it "returns only the requested destination tip" do
    user = create_onboarded_adult(email: "tips-home@example.com")

    get "/api/v1/first_run_tips", params: { destination: "home" }, headers: headers_for(user)

    expect(response).to have_http_status(:ok)
    tip = response.parsed_body["tip"]
    expect(tip["key"]).to eq("home")
    expect(tip["label"]).to eq("Start here")
    expect(tip["body"]).to include("Personal workspace")
    expect(tip["body"]).not_to include("My Work", "Inbox")
    expect(response.body).not_to include(user.email)
  end

  it "keeps a dismissal after a workspace switch and does not dismiss other keys" do
    user = create_onboarded_adult(email: "tips-dismiss@example.com")
    organization = create_organization(name: "Tip Org")
    create_membership(organization: organization, user: user, role: OrganizationMembership::PARTICIPANT)

    post "/api/v1/first_run_tips/my_work/dismiss", headers: headers_for(user)
    expect(response).to have_http_status(:no_content)

    get "/api/v1/first_run_tips", params: { destination: "my_work" }, headers: headers_for(user)
    expect(response.parsed_body["tip"]).to be_nil

    get "/api/v1/first_run_tips", params: { destination: "home" }, headers: headers_for(user)
    expect(response.parsed_body.dig("tip", "key")).to eq("home")

    switch_to!(user, organization.workspace)

    get "/api/v1/first_run_tips", params: { destination: "my_work" }, headers: headers_for(user)
    expect(response.parsed_body["tip"]).to be_nil
    expect(FirstRunTipDismissal.where(user: user, tip_key: "my_work").count).to eq(1)
  end

  it "replays only the signed-in user's dismissals" do
    first = create_onboarded_adult(email: "tips-replay-a@example.com")
    second = create_onboarded_adult(email: "tips-replay-b@example.com")
    post "/api/v1/first_run_tips/home/dismiss", headers: headers_for(first)
    post "/api/v1/first_run_tips/home/dismiss", headers: headers_for(second)

    post "/api/v1/first_run_tips/replay", headers: headers_for(first)

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body["restored_keys"]).to eq([ "home" ])
    expect(FirstRunTipDismissal.where(user: first)).to be_empty
    expect(FirstRunTipDismissal.where(user: second, tip_key: "home")).to exist

    get "/api/v1/first_run_tips", params: { destination: "home" }, headers: headers_for(first)
    expect(response.parsed_body.dig("tip", "key")).to eq("home")
  end

  it "uses restricted copy for minors and for adults who cannot show a public identity" do
    minor = create_onboarded_adult(email: "tips-minor@example.com")
    minor.update!(age_status: AgeStatusCalculator::MINOR, onboarding_path: "organization_invited")

    get "/api/v1/first_run_tips", params: { destination: "home" }, headers: headers_for(minor)
    body = response.parsed_body.dig("tip", "body")
    expect(body).to eq("Home shows the next action for this workspace.")
    expect(body).not_to include("Personal", "credit", "public")
    expect(response.body).not_to include(minor.email)

    private_adult = create_onboarded_adult(email: "tips-private@example.com")
    private_adult.update!(onboarding_path: "organization_invited")
    private_adult.age_visibility_preference.update!(public_identity_confirmed: false)

    get "/api/v1/first_run_tips", params: { destination: "profile" }, headers: headers_for(private_adult)
    expect(response.parsed_body.dig("tip", "body")).to eq(
      "Profile is your contribution record. Settings holds preferences for this account."
    )
    expect(response.parsed_body.dig("tip", "body")).not_to include("public")

    get "/api/v1/first_run_tips", params: { destination: "home" }, headers: headers_for(private_adult)
    expect(response.parsed_body.dig("tip", "body")).to include("Personal workspace")
  end

  it "rejects unknown keys without writing a dismissal and rejects unauthenticated and suspended callers" do
    user = create_onboarded_adult(email: "tips-reject@example.com")

    post "/api/v1/first_run_tips/not-a-tip/dismiss", headers: headers_for(user)
    expect(response).to have_http_status(:not_found)
    expect(FirstRunTipDismissal.where(user: user)).to be_empty

    get "/api/v1/first_run_tips", params: { destination: "explore" }, headers: headers_for(user)
    expect(response).to have_http_status(:not_found)

    get "/api/v1/first_run_tips", params: { destination: "home" }
    expect(response).to have_http_status(:unauthorized)

    user.update!(status: User::SUSPENDED)
    get "/api/v1/first_run_tips", params: { destination: "home" }, headers: headers_for(user)
    expect(response).to have_http_status(:forbidden)
  end

  it "treats a second dismiss as still dismissed and an empty replay as success" do
    user = create_onboarded_adult(email: "tips-idempotent@example.com")
    post "/api/v1/first_run_tips/inbox/dismiss", headers: headers_for(user)
    post "/api/v1/first_run_tips/inbox/dismiss", headers: headers_for(user)
    expect(response).to have_http_status(:no_content)
    expect(FirstRunTipDismissal.where(user: user, tip_key: "inbox").count).to eq(1)

    other = create_onboarded_adult(email: "tips-empty-replay@example.com")
    post "/api/v1/first_run_tips/replay", headers: headers_for(other)
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body["restored_keys"]).to eq([])
  end
end
