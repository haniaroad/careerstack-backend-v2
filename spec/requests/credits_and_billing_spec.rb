# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Credits API", type: :request do
  let(:headers) { auth_headers(firebase_uid: "uid-credits", email: "credits@example.com") }

  before do
    create_onboarded_adult(email: "credits@example.com", firebase_uid: "uid-credits")
  end

  it "returns the personal balance for the active workspace" do
    get "/api/v1/credits", headers: headers

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body["credits"]).to include(
      "remaining" => 1,
      "trial_remaining" => 1,
      "owner_type" => "user"
    )
  end

  it "returns history newest first" do
    user = User.find_by!(email: "credits@example.com")
    Credits::Consume.call(owner: user, reason: "project_create", idempotency_key: "hist-api-1", actor_user: user)

    get "/api/v1/credits/history", headers: headers

    expect(response).to have_http_status(:ok)
    events = response.parsed_body["entries"].map { |row| row["event"] }
    expect(events).to eq(%w[consume grant])
  end

  it "includes credits on the session payload" do
    get "/api/v1/session", headers: headers

    expect(response.parsed_body["credits"]).to include("remaining" => 1)
  end
end

RSpec.describe "Billing checkout authz", type: :request do
  it "rejects purchase for minors" do
    user = create_user(email: "minor@example.com", firebase_uid: "uid-minor", status: User::ACTIVE, age_status: AgeStatusCalculator::MINOR)
    headers = auth_headers(firebase_uid: "uid-minor", email: "minor@example.com")

    # Give them an org workspace so they can authenticate into shell-like state
    organization = create_organization
    create_membership(organization: organization, user: user)
    user.update!(active_workspace: organization.workspace)

    post "/api/v1/billing/checkout_sessions", headers: headers, as: :json

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body.dig("error", "code")).to eq("purchase_ineligible")
  end
end

RSpec.describe "Stripe webhooks", type: :request do
  it "rejects requests when ProcessWebhook reports an invalid signature" do
    allow(Billing::ProcessWebhook).to receive(:call).and_raise(
      DomainError.new("Invalid Stripe signature", code: "invalid_stripe_signature", status: :bad_request)
    )

    post "/api/v1/stripe/webhooks",
         params: "{}",
         headers: { "CONTENT_TYPE" => "application/json", "HTTP_STRIPE_SIGNATURE" => "bad" }

    expect(response).to have_http_status(:bad_request)
    expect(response.parsed_body.dig("error", "code")).to eq("invalid_stripe_signature")
  end
end
