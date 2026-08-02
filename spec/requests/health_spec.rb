# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Health", type: :request do
  it "returns ok without authentication" do
    get "/health"

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to eq("status" => "ok")
  end

  it "aliases /up to health" do
    get "/up"
    expect(response).to have_http_status(:ok)
  end
end
