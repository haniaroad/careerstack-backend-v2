# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::RunTaskReview do
  let(:user) { create_onboarded_adult(email: "run-review@example.com", firebase_uid: "uid-run-review") }

  after { Ai::Provider.unstub! }

  it "includes project context and experience level in the review prompt" do
    allow(Ai::Config).to receive(:configured?).and_return(true)
    allow(Ai::Config).to receive(:nonessential_ai_stopped?).and_return(false)

    project = Projects::CreateDraft.call(
      user: user,
      workspace: user.personal_workspace,
      title: "Horror Game Design in Unity",
      summary: "Build a short horror prototype"
    )
    project.update!(
      objective: "Ship a playable horror scene",
      definition_of_done: "Playable build with atmosphere",
      skills: [ "Unity", "Audio" ],
      expected_duration: "2 weeks",
      submission_expectations: "Repo link + notes",
      proposed_tasks: [
        {
          "title" => "Add Sound Effects and Music",
          "summary" => "Incorporate SFX and music for atmosphere",
          "recommended_due_date" => (Date.current + 7).iso8601,
          "submission_expectations" => "Unity project with audio integrated"
        }
      ],
      ends_on: Date.current + 14
    )
    AiGeneration.create!(
      user: user,
      workspace: user.personal_workspace,
      project: project,
      use_case: AiGeneration::USE_CASE_PROJECT_DRAFT,
      status: AiGeneration::STATUS_SUCCEEDED,
      prompt: "horror game",
      prompt_digest: "digest-#{SecureRandom.hex(8)}",
      constraints: { "skill_level" => "beginner", "time_available" => "2 weeks" },
      succeeded_at: Time.current
    )
    Projects::Confirm.call(project: project, user: user)
    task = project.tasks.first
    submission = Tasks::Submit.call(task: task, user: user, body: "Added spooky ambience", enqueue_review: false)[:submission]

    captured_messages = nil
    provider = Object.new
    provider.define_singleton_method(:complete_structured) do |**kwargs|
      captured_messages = kwargs[:messages]
      Ai::CompletionResult.new(
        content: {
          decision: "corrections_requested",
          feedback: "Need clearer evidence of music integration",
          unmet_requirements: [ "Show soundtrack wiring" ],
          next_action: "Attach a short writeup of audio setup",
          analysis_incomplete: false,
          unsupported_items: []
        }.to_json,
        model: "openai/gpt-4o-mini",
        prompt_tokens: 10,
        completion_tokens: 20,
        total_tokens: 30
      )
    end
    Ai::Provider.stub!(provider)

    review = AiReview.create!(
      task: task,
      task_submission: submission,
      user: user,
      status: AiReview::STATUS_PENDING,
      content_fingerprint: submission.content_fingerprint
    )

    described_class.call(review: review)

    user_text = captured_messages.find { |m| m[:role] == "user" }[:content]
    expect(user_text).to include("Horror Game Design in Unity")
    expect(user_text).to include("Ship a playable horror scene")
    expect(user_text).to include("Unity, Audio")
    expect(user_text).to include("Participant experience level: #{user.profile.experience_level}")
    expect(user_text).to include("Project skill level constraint: beginner")
    expect(user_text).to include("Add Sound Effects and Music")
    expect(user_text).to include("Incorporate SFX and music for atmosphere")
    expect(review.reload.prompt_version).to eq("v2")
    expect(review.decision).to eq(AiReview::DECISION_CORRECTIONS_REQUESTED)
  end
end
