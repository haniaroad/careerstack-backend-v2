# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Correlation ID", type: :request do
  it "echoes a client-supplied X-Request-Id" do
    get "/health", headers: { "X-Request-Id" => "client-trace-1" }

    expect(response.headers["X-Request-Id"]).to eq("client-trace-1")
  end

  it "generates an X-Request-Id when omitted" do
    get "/health"

    expect(response.headers["X-Request-Id"]).to be_present
  end
end
