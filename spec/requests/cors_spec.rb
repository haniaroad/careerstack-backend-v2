# frozen_string_literal: true

require "rails_helper"

RSpec.describe "CORS", type: :request do
  around do |example|
    previous = ENV["CORS_ORIGINS"]
    ENV["CORS_ORIGINS"] = "http://localhost:5173,https://staging.example.com"
    example.run
  ensure
    ENV["CORS_ORIGINS"] = previous
  end


  it "allows an allowlisted origin" do
    options "/health",
            headers: {
              "Origin" => "http://localhost:5173",
              "Access-Control-Request-Method" => "GET"
            }

    expect(response.headers["Access-Control-Allow-Origin"]).to eq("http://localhost:5173")
  end

  it "denies an unknown origin" do
    options "/health",
            headers: {
              "Origin" => "https://evil.example",
              "Access-Control-Request-Method" => "GET"
            }

    expect(response.headers["Access-Control-Allow-Origin"]).to be_nil
  end
end
