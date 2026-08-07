# frozen_string_literal: true

require "rails_helper"

RSpec.describe "AI project generations API", type: :request do
  let(:user) { create_onboarded_adult(email: "aigen@example.com", firebase_uid: "uid-aigen") }
  let(:headers) { auth_headers(firebase_uid: user.firebase_uid, email: user.email) }
  let(:future_end) { (Date.current + 21).iso8601 }
  let(:valid_payload) do
    {
      "title" => "API Portfolio",
      "summary" => "Build a site",
      "learning_objective" => "Learn HTML",
      "project_type" => "web",
      "expected_duration" => "2 weeks",
      "project_end_date" => future_end,
      "definition_of_done" => "Live URL",
      "skills_demonstrated" => [ "HTML" ],
      "roles_needed" => [ "Builder" ],
      "submission_expectations" => "URL",
      "proposed_tasks" => [
        {
          "title" => "Task 1",
          "summary" => "Do thing",
          "recommended_due_date" => (Date.current + 5).iso8601,
          "submission_expectations" => "Link"
        }
      ]
    }
  end

  after { Ai::Provider.unstub! }

  before do
    allow(Ai::Config).to receive(:configured?).and_return(true)
    allow(Ai::Provider).to receive(:complete_structured).and_return(
      Ai::CompletionResult.new(content: JSON.generate(valid_payload), model: "openai/gpt-4o-mini", total_tokens: 12)
    )
  end

  it "creates, polls, accepts, and confirms without charging on generate" do
    post "/api/v1/ai/project_generations",
         params: {
           prompt: "Make a portfolio",
           constraints: { skill_level: "beginner", time_available: "2 weeks" },
           client_draft_key: "ui-draft-1"
         }.to_json,
         headers: headers.merge("CONTENT_TYPE" => "application/json")
    expect(response).to have_http_status(:accepted)
    generation_id = response.parsed_body.dig("generation", "id")
    gen = response.parsed_body.fetch("generation")
    expect(gen["status"]).to eq("succeeded"), "expected succeeded, got #{gen.inspect}"
    expect(Credits::Balance.remaining(owner: user)).to eq(1)

    get "/api/v1/ai/project_generations/#{generation_id}", headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig("generation", "result", "title")).to eq("API Portfolio")

    post "/api/v1/ai/project_generations/#{generation_id}/accept", headers: headers
    expect(response).to have_http_status(:ok)
    project_id = response.parsed_body.dig("project", "id")
    expect(response.parsed_body.dig("project", "source")).to eq("ai")
    expect(Credits::Balance.remaining(owner: user)).to eq(1)

    post "/api/v1/projects/#{project_id}/confirm", headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig("project", "status")).to eq("active")
    expect(Credits::Balance.remaining(owner: user)).to eq(0)
  end

  it "rejects unauthenticated create" do
    post "/api/v1/ai/project_generations",
         params: { prompt: "x" }.to_json,
         headers: { "CONTENT_TYPE" => "application/json" }
    expect(response).to have_http_status(:unauthorized)
  end

  it "hides other users generations" do
    post "/api/v1/ai/project_generations",
         params: { prompt: "Mine", client_draft_key: "mine" }.to_json,
         headers: headers.merge("CONTENT_TYPE" => "application/json")
    generation_id = response.parsed_body.dig("generation", "id")

    other = create_onboarded_adult(email: "other-ai@example.com", firebase_uid: "uid-other-ai")
    get "/api/v1/ai/project_generations/#{generation_id}",
        headers: auth_headers(firebase_uid: other.firebase_uid, email: other.email)
    expect(response).to have_http_status(:not_found)
  end

  it "returns ai_unavailable when kill switch is on" do
    allow(Ai::Config).to receive(:nonessential_ai_stopped?).and_return(true)
    post "/api/v1/ai/project_generations",
         params: { prompt: "Nope" }.to_json,
         headers: headers.merge("CONTENT_TYPE" => "application/json")
    expect(response).to have_http_status(:service_unavailable)
    expect(response.parsed_body.dig("error", "code")).to eq("ai_unavailable")
  end
end
