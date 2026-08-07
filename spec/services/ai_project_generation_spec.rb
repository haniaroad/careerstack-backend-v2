# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Ai project generation services" do
  let(:user) { create_onboarded_adult(email: "ai@example.com", firebase_uid: "uid-ai") }
  let(:workspace) { user.personal_workspace }
  let(:future_end) { (Date.current + 21).iso8601 }
  let(:valid_payload) do
    {
      "title" => "Portfolio Landing Page",
      "summary" => "Build a personal portfolio site.",
      "learning_objective" => "Ship a responsive landing page.",
      "project_type" => "web",
      "expected_duration" => "2 weeks",
      "project_end_date" => future_end,
      "definition_of_done" => "Deployed page with about and projects sections.",
      "skills_demonstrated" => [ "HTML", "CSS" ],
      "roles_needed" => [ "Solo builder" ],
      "submission_expectations" => "Share a public URL.",
      "proposed_tasks" => [
        {
          "title" => "Wireframe",
          "summary" => "Sketch layout",
          "recommended_due_date" => (Date.current + 7).iso8601,
          "submission_expectations" => "Link to wireframe"
        }
      ]
    }
  end

  after { Ai::Provider.unstub! }

  before do
    allow(Ai::Config).to receive(:configured?).and_return(true)
  end

  def stub_provider!(payload: valid_payload, raise_error: nil)
    provider = Object.new
    payload_json = payload.is_a?(String) ? payload : JSON.generate(payload)
    provider.define_singleton_method(:complete_structured) do |**_|
      raise raise_error if raise_error

      Ai::CompletionResult.new(
        content: payload_json,
        model: "openai/gpt-4o-mini",
        prompt_tokens: 10,
        completion_tokens: 20,
        total_tokens: 30
      )
    end
    Ai::Provider.stub!(provider)
  end

  it "runs generation successfully without consuming credits" do
    stub_provider!
    expect {
      generation = Ai::CreateProjectGeneration.call(
        user: user,
        workspace: workspace,
        prompt: "Build a portfolio site",
        client_draft_key: "draft-1"
      )
      Ai::RunProjectDraftGeneration.call(generation: generation)
      expect(generation.reload).to be_succeeded
      expect(generation.result["title"]).to eq("Portfolio Landing Page")
    }.not_to change { Credits::Balance.remaining(owner: user) }
  end

  it "marks schema failures as failed and retryable without consuming allowance" do
    stub_provider!(payload: { "title" => "Nope" })
    generation = Ai::CreateProjectGeneration.call(
      user: user,
      workspace: workspace,
      prompt: "Bad schema",
      client_draft_key: "draft-bad"
    )
    Ai::RunProjectDraftGeneration.call(generation: generation)
    expect(generation.reload).to be_failed
    expect(generation.error_code).to eq("ai_schema_invalid")
    expect(generation.retryable).to be(true)

    stub_provider!
    again = Ai::CreateProjectGeneration.call(
      user: user,
      workspace: workspace,
      prompt: "Retry",
      client_draft_key: "draft-bad"
    )
    expect(again).to be_persisted
  end

  it "blocks when kill switch is on" do
    allow(Ai::Config).to receive(:nonessential_ai_stopped?).and_return(true)
    expect {
      Ai::CreateProjectGeneration.call(user: user, workspace: workspace, prompt: "X")
    }.to raise_error(DomainError) { |e| expect(e.code).to eq("ai_unavailable") }
  end

  it "rate limits successful generations" do
    stub_provider!
    allow(Ai::Config).to receive(:success_rate_limit_per_day).and_return(1)
    first = Ai::CreateProjectGeneration.call(user: user, workspace: workspace, prompt: "One", client_draft_key: "a")
    Ai::RunProjectDraftGeneration.call(generation: first)

    expect {
      Ai::CreateProjectGeneration.call(user: user, workspace: workspace, prompt: "Two", client_draft_key: "b")
    }.to raise_error(DomainError) { |e| expect(e.code).to eq("ai_rate_limited") }
  end

  it "blocks second successful generation for the same draft key" do
    stub_provider!
    first = Ai::CreateProjectGeneration.call(user: user, workspace: workspace, prompt: "One", client_draft_key: "same")
    Ai::RunProjectDraftGeneration.call(generation: first)
    Ai::AcceptProjectGeneration.call(generation: first.reload, user: user, workspace: workspace)

    expect {
      Ai::CreateProjectGeneration.call(user: user, workspace: workspace, prompt: "Two", client_draft_key: "same")
    }.to raise_error(DomainError) { |e| expect(e.code).to eq("ai_allowance_exhausted") }
  end

  it "accepts generation into a draft and confirm still consumes one credit" do
    stub_provider!
    generation = Ai::CreateProjectGeneration.call(
      user: user,
      workspace: workspace,
      prompt: "Portfolio",
      client_draft_key: "accept-1"
    )
    Ai::RunProjectDraftGeneration.call(generation: generation)
    project = Ai::AcceptProjectGeneration.call(generation: generation.reload, user: user, workspace: workspace)
    expect(project).to be_draft
    expect(project.source).to eq("ai")
    expect(project.proposed_tasks).not_to be_empty
    expect(Credits::Balance.remaining(owner: user)).to eq(1)

    Projects::Confirm.call(project: project, user: user)
    expect(project.reload).to be_active
    expect(Credits::Balance.remaining(owner: user)).to eq(0)
  end
end
