# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Error envelope", type: :request do
  it "returns not_found envelope for unknown authenticated paths" do
    get "/does-not-exist", headers: { "Authorization" => "Bearer test-token" }

    expect(response).to have_http_status(:not_found)
    expect(response.parsed_body).to match(
      "error" => hash_including(
        "code" => "not_found",
        "message" => "Resource not found",
        "request_id" => be_present
      )
    )
  end

  it "returns unauthenticated envelope for protected paths" do
    get "/does-not-exist"

    expect(response).to have_http_status(:unauthorized)
    expect(response.parsed_body).to match(
      "error" => hash_including(
        "code" => "unauthenticated",
        "message" => "Authentication required",
        "request_id" => be_present
      )
    )
  end
end
