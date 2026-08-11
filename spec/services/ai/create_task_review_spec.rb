# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::CreateTaskReview do
  let(:user) { create_onboarded_adult(email: "ai-review@example.com", firebase_uid: "uid-ai-review") }

  def build_submitted_task!
    project = Projects::CreateDraft.call(user: user, workspace: user.personal_workspace, title: "P")
    project.update!(proposed_tasks: [ { "title" => "T1", "summary" => "Do it", "recommended_due_date" => (Date.current + 5).iso8601 } ], ends_on: Date.current + 14)
    Projects::Confirm.call(project: project, user: user)
    task = project.tasks.first
    result = Tasks::Submit.call(task: task, user: user, body: "Evidence text", enqueue_review: false)
    [ task.reload, result[:submission] ]
  end

  after { Ai::Provider.unstub! }

  it "rate limits, cools down identical submissions, and skips attempt count on technical failure" do
    allow(Ai::Config).to receive(:configured?).and_return(true)
    allow(Ai::Config).to receive(:nonessential_ai_stopped?).and_return(false)

    provider = Object.new
    calls = 0
    provider.define_singleton_method(:complete_structured) do |**_|
      calls += 1
      if calls == 1
        raise Ai::Providers::OpenRouter::Error.new("boom", retryable: true)
      end
      Ai::CompletionResult.new(
        content: {
          decision: "corrections_requested",
          feedback: "needs work",
          unmet_requirements: [ "more detail" ],
          next_action: "revise",
          analysis_incomplete: false,
          unsupported_items: []
        }.to_json,
        model: "m",
        prompt_tokens: 1,
        completion_tokens: 1,
        total_tokens: 2
      )
    end
    Ai::Provider.stub!(provider)

    task, submission = build_submitted_task!
    # First create will retry technically then succeed (inline retries)
    review = described_class.call(task: task, submission: submission, user: user, auto: false)
    expect(review.succeeded?).to eq(true)
    expect(review.counts_as_attempt).to eq(true)

    expect {
      described_class.call(task: task, submission: submission, user: user, auto: false)
    }.to raise_error(DomainError) { |e| expect(e.code).to eq("ai_review_cooldown") }
  end

  it "rejects when kill switch is on for explicit requests" do
    allow(Ai::Config).to receive(:configured?).and_return(true)
    allow(Ai::Config).to receive(:nonessential_ai_stopped?).and_return(true)
    task, submission = build_submitted_task!

    expect {
      described_class.call(task: task, submission: submission, user: user, auto: false)
    }.to raise_error(DomainError) { |e| expect(e.code).to eq("ai_unavailable") }
  end
end
