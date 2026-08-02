# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Readiness", type: :request do
  it "returns ready when the database is reachable" do
    get "/ready"

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to eq("status" => "ready")
  end

  it "returns not ready when the database is unreachable" do
    allow(ActiveRecord::Base.connection).to receive(:execute).and_raise(ActiveRecord::ConnectionNotEstablished)

    get "/ready"

    expect(response).to have_http_status(:service_unavailable)
    expect(response.parsed_body["status"]).to eq("not_ready")
  end
end
