# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Age-up visibility review", type: :request do
  let(:organization) { create_organization(name: "Bridge Academy") }

  # An org-invited user who has just been promoted to adult by age-up detection.
  def create_aged_up_user(email: "agedup@example.com")
    user = create_user(email: email, status: User::ACTIVE)
    user.create_profile!(minimum_profile_attributes(date_of_birth: 18.years.ago.to_date))
    user.update!(onboarding_path: "organization_invited", age_status: AgeStatusCalculator::ADULT)
    create_membership(organization: organization, user: user)
    user.create_age_visibility_preference!(visibility_review_required: true)
    Workspaces::EnsurePersonal.call(user: user)
    user.reload
  end

  it "keeps the profile private while review is pending" do
    user = create_aged_up_user

    get "/api/v1/session", headers: headers_for(user)

    expect(response.parsed_body["age_visibility"]).to include(
      "visibility_review_required" => true,
      "public_identity_confirmed" => false
    )
    expect(response.parsed_body.dig("user", "public_identity_visible")).to be(false)
  end

  it "reveals public identity after explicit confirmation" do
    user = create_aged_up_user

    patch "/api/v1/age_visibility", params: { decision: "confirm" }, headers: headers_for(user), as: :json

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body["age_visibility"]).to include(
      "visibility_review_required" => false,
      "public_identity_confirmed" => true
    )
    expect(response.parsed_body.dig("user", "public_identity_visible")).to be(true)
    expect(user.age_visibility_preference.reload.confirmed_at).to be_present
  end

  it "allows the user to reverse a previous confirmation" do
    user = create_aged_up_user
    patch "/api/v1/age_visibility", params: { decision: "confirm" }, headers: headers_for(user), as: :json
    expect(response).to have_http_status(:ok)

    patch "/api/v1/age_visibility", params: { decision: "reverse" }, headers: headers_for(user), as: :json

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig("age_visibility", "public_identity_confirmed")).to be(false)
    expect(response.parsed_body.dig("user", "public_identity_visible")).to be(false)
    expect(user.age_visibility_preference.reload.confirmed_at).to be_nil
  end

  it "forbids a minor from changing visibility" do
    minor = create_user(email: "minor@example.com", status: User::ACTIVE, age_status: AgeStatusCalculator::MINOR)
    minor.create_age_visibility_preference!

    patch "/api/v1/age_visibility", params: { decision: "confirm" }, headers: headers_for(minor), as: :json

    expect(response).to have_http_status(:forbidden)
    expect(minor.age_visibility_preference.reload.public_identity_confirmed).to be(false)
  end

  it "rejects an unrecognized decision" do
    user = create_aged_up_user

    patch "/api/v1/age_visibility", params: { decision: "maybe" }, headers: headers_for(user), as: :json

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body.dig("error", "code")).to eq("validation_error")
  end

  it "rejects a missing decision" do
    user = create_aged_up_user

    patch "/api/v1/age_visibility", params: {}, headers: headers_for(user), as: :json

    expect(response).to have_http_status(:unprocessable_entity)
  end

  it "treats independent adults as publicly visible without a review" do
    user = create_onboarded_adult(email: "independent@example.com")

    get "/api/v1/session", headers: headers_for(user)

    expect(response.parsed_body.dig("user", "public_identity_visible")).to be(true)
    expect(response.parsed_body.dig("age_visibility", "visibility_review_required")).to be(false)
  end
end
