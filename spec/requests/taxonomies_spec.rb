# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Taxonomies", type: :request do
  let(:user) { create_onboarded_adult(email: "reader@example.com") }

  it "requires authentication" do
    get "/api/v1/taxonomies"

    expect(response).to have_http_status(:unauthorized)
  end

  it "lists every controlled taxonomy with stable term ids" do
    get "/api/v1/taxonomies", headers: headers_for(user)

    expect(response).to have_http_status(:ok)
    taxonomies = response.parsed_body["taxonomies"]
    expect(taxonomies.map { |taxonomy| taxonomy["key"] }).to eq(
      %w[experience_levels organization_goals organization_structures roles]
    )

    roles = taxonomies.find { |taxonomy| taxonomy["key"] == "roles" }
    expect(roles["terms"].map { |t| t["key"] }).to eq(
      %w[software_engineer data_analyst product_designer product_manager cybersecurity_analyst ai_ml_engineer other]
    )
    expect(roles["terms"].map { |t| t["id"] }).to all(match(/\A[0-9a-f-]{36}\z/))
  end

  it "flags the Other option on taxonomies that offer one" do
    get "/api/v1/taxonomies", headers: headers_for(user)

    taxonomies = response.parsed_body["taxonomies"].index_by { |taxonomy| taxonomy["key"] }

    %w[roles organization_structures organization_goals].each do |key|
      others = taxonomies.fetch(key)["terms"].select { |term| term["is_other"] }
      expect(others.map { |term| term["key"] }).to eq([ "other" ]), "expected exactly one Other term in #{key}"
    end

    expect(taxonomies.fetch("experience_levels")["terms"].map { |term| term["key"] }).to eq(
      Profile::EXPERIENCE_LEVELS
    )
  end
end
