# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Tasks and AI review API", type: :request do
  let(:user) { create_onboarded_adult(email: "tasks@example.com", firebase_uid: "uid-tasks") }
  let(:headers) { auth_headers(firebase_uid: user.firebase_uid, email: user.email).merge("CONTENT_TYPE" => "application/json") }
  let(:other) { create_onboarded_adult(email: "other-tasks@example.com", firebase_uid: "uid-tasks-other") }
  let(:other_headers) { auth_headers(firebase_uid: other.firebase_uid, email: other.email).merge("CONTENT_TYPE" => "application/json") }

  def stub_review_provider(decision: "approved", unmet: [], next_action: "Ship it", incomplete: false)
    provider = Object.new
    provider.define_singleton_method(:complete_structured) do |**_|
      Ai::CompletionResult.new(
        content: {
          decision: decision,
          feedback: "Review feedback",
          unmet_requirements: unmet,
          next_action: next_action,
          analysis_incomplete: incomplete,
          unsupported_items: []
        }.to_json,
        model: "openai/gpt-4o-mini",
        prompt_tokens: 10,
        completion_tokens: 20,
        total_tokens: 30
      )
    end
    Ai::Provider.stub!(provider)
  end

  after { Ai::Provider.unstub! }

  def create_active_project_with_tasks!
    project = Projects::CreateDraft.call(
      user: user,
      workspace: user.personal_workspace,
      title: "Solo with tasks",
      summary: "Practice"
    )
    project.update!(
      proposed_tasks: [
        {
          "title" => "Build landing page",
          "summary" => "Ship a responsive page",
          "recommended_due_date" => (Date.current + 7).iso8601,
          "submission_expectations" => "Link + short writeup"
        }
      ],
      ends_on: Date.current + 14
    )
    Projects::Confirm.call(project: project, user: user)
    project.reload
  end

  before do
    allow(Ai::Config).to receive(:configured?).and_return(true)
    allow(Ai::Config).to receive(:nonessential_ai_stopped?).and_return(false)
    stub_review_provider
  end

  it "materializes tasks on confirm, submits, reviews, corrections, resubmits, approves" do
    stub_review_provider(decision: "corrections_requested", unmet: [ "Missing writeup" ], next_action: "Add a writeup")
    project = create_active_project_with_tasks!
    expect(project.tasks.count).to eq(1)
    task = project.tasks.first
    expect(task.status).to eq("pending")

    get "/api/v1/tasks", headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch("tasks").map { |t| t["id"] }).to include(task.id)

    post "/api/v1/tasks/#{task.id}/submissions",
         params: { body: "First attempt", links: [ "https://example.com/demo" ] }.to_json,
         headers: headers
    expect(response).to have_http_status(:created)
    expect(response.parsed_body.dig("task", "status")).to eq("corrections_requested")
    review_id = response.parsed_body.dig("review", "id")
    expect(review_id).to be_present

    stub_review_provider(decision: "approved", next_action: "None")
    post "/api/v1/tasks/#{task.id}/submissions",
         params: { body: "Revised writeup with details", links: [ "https://example.com/demo" ] }.to_json,
         headers: headers
    expect(response).to have_http_status(:created)
    expect(response.parsed_body.dig("task", "status")).to eq("approved")
    expect(task.reload.on_time).to eq(true)

    post "/api/v1/ai/reviews/#{review_id}/reports",
         params: { report_type: "inaccurate", reason_category: "wrong_decision", details: "Too harsh" }.to_json,
         headers: headers
    expect(response).to have_http_status(:created)
    expect(task.reload.status).to eq("approved")
  end

  it "rejects disallowed link schemes and isolates authz" do
    project = create_active_project_with_tasks!
    task = project.tasks.first

    post "/api/v1/tasks/#{task.id}/submissions",
         params: { body: "x", links: [ "javascript:alert(1)" ] }.to_json,
         headers: headers
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body.dig("error", "code")).to eq("validation_error")
    expect(task.reload.status).to eq("pending")

    post "/api/v1/tasks/#{task.id}/submissions",
         params: { body: "hijack" }.to_json,
         headers: other_headers
    expect(response).to have_http_status(:not_found)
  end

  it "rejects more than three files" do
    project = create_active_project_with_tasks!
    task = project.tasks.first

    blobs = 4.times.map do |i|
      ActiveStorage::Blob.create_and_upload!(
        io: StringIO.new("hello #{i}"),
        filename: "note#{i}.txt",
        content_type: "text/plain"
      )
    end

    post "/api/v1/tasks/#{task.id}/submissions",
         params: { body: "files", signed_blob_ids: blobs.map(&:signed_id) }.to_json,
         headers: headers
    expect(response).to have_http_status(:unprocessable_entity)
    expect(task.reload.status).to eq("pending")
  end

  it "blocks kill switch and respects cooldown / concurrent review codes on explicit retry" do
    project = create_active_project_with_tasks!
    task = project.tasks.first

    allow(Ai::Config).to receive(:nonessential_ai_stopped?).and_return(true)
    post "/api/v1/tasks/#{task.id}/submissions",
         params: { body: "While kill switch on" }.to_json,
         headers: headers
    expect(response).to have_http_status(:created)
    expect(response.parsed_body["review"]).to be_nil
    expect(task.reload.status).to eq("submitted")

    allow(Ai::Config).to receive(:nonessential_ai_stopped?).and_return(false)
    stub_review_provider(decision: "approved")
    post "/api/v1/tasks/#{task.id}/ai_reviews", headers: headers
    expect(response).to have_http_status(:accepted)
    expect(task.reload.status).to eq("approved")

    post "/api/v1/tasks/#{task.id}/ai_reviews", headers: headers
    expect(response.status).to be_in([ 409, 422, 429 ])
  end

  it "marks mixed https evidence as analysis_incomplete without claiming URL review" do
    stub_review_provider(decision: "corrections_requested", unmet: [ "Need clearer writeup" ], incomplete: true)
    project = create_active_project_with_tasks!
    task = project.tasks.first

    post "/api/v1/tasks/#{task.id}/submissions",
         params: { body: "Text plus link", links: [ "https://github.com/example/repo" ] }.to_json,
         headers: headers
    expect(response).to have_http_status(:created)
    review = response.parsed_body.fetch("review")
    expect(review["analysis_incomplete"]).to eq(true)
    expect(review["unsupported_items"]).not_to be_empty
  end

  it "restores create credit on cancel after submissions" do
    project = create_active_project_with_tasks!
    task = project.tasks.first
    post "/api/v1/tasks/#{task.id}/submissions",
         params: { body: "Work" }.to_json,
         headers: headers
    expect(response).to have_http_status(:created)

    post "/api/v1/projects/#{project.id}/cancel", headers: headers
    expect(response).to have_http_status(:ok)
    expect(Credits::Balance.remaining(owner: user)).to eq(1)
  end
end
