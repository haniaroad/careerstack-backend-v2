# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Task maintenance API", type: :request do
  def solo_project!(creator)
    project = Projects::CreateDraft.call(
      user: creator,
      workspace: creator.personal_workspace,
      title: "Editable solo"
    )
    project.update!(
      ends_on: Date.current + 30,
      proposed_tasks: [
        {
          "title" => "Draft the page",
          "summary" => "Original description",
          "recommended_due_date" => (Date.current + 4).iso8601,
          "submission_expectations" => "A writeup",
          "reference_video_url" => "https://youtu.be/aqz-KE-bpKQ"
        }
      ]
    )
    Projects::Confirm.call(project: project, user: creator)
    project.reload
  end

  it "lets the creator update and delete a non-approved task" do
    creator = create_onboarded_adult(email: "edit-creator-#{SecureRandom.hex(3)}@example.com")
    project = solo_project!(creator)
    task = project.tasks.first
    expect(task.reference_video_url).to eq("https://youtu.be/aqz-KE-bpKQ")
    review_context = Ai::RunTaskReview.new(review: instance_double(AiReview, task: task)).send(:review_context_block)
    expect(review_context).to include("Draft the page")
    expect(review_context).not_to include("youtu.be")

    patch "/api/v1/tasks/#{task.id}",
          params: {
            title: "Revised title",
            acceptance_criteria: "Updated description",
            due_on: (Date.current + 6).iso8601,
            reference_video_url: "https://www.youtube.com/watch?v=9bZkp7q19f0"
          },
          headers: headers_for(creator),
          as: :json
    expect(response).to have_http_status(:ok)
    body = response.parsed_body.fetch("task")
    expect(body["title"]).to eq("Revised title")
    expect(body["acceptance_criteria"]).to eq("Updated description")
    expect(body["reference_video_url"]).to eq("https://www.youtube.com/watch?v=9bZkp7q19f0")
    expect(body["status"]).to eq("pending")
    expect(body["assignee_id"]).to eq(creator.id)

    task.submissions.create!(
      submitted_by: creator,
      attempt_number: 1,
      body: "Earlier note",
      content_fingerprint: "fp",
      submitted_at: Time.current
    )
    delete "/api/v1/tasks/#{task.id}", headers: headers_for(creator)
    expect(response).to have_http_status(:no_content)
    expect(Task.exists?(task.id)).to be(false)
    expect(TaskSubmission.where(task_id: task.id)).to be_empty
  end

  it "rejects a non-YouTube reference URL, approved edits, and edits outside the open work phase" do
    creator = create_onboarded_adult(email: "edit-lock-#{SecureRandom.hex(3)}@example.com")
    project = solo_project!(creator)
    task = project.tasks.first

    patch "/api/v1/tasks/#{task.id}",
          params: { reference_video_url: "https://vimeo.com/123" },
          headers: headers_for(creator),
          as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(task.reload.reference_video_url).to eq("https://youtu.be/aqz-KE-bpKQ")

    task.update!(status: Task::STATUS_APPROVED)
    patch "/api/v1/tasks/#{task.id}",
          params: { title: "Nope" },
          headers: headers_for(creator),
          as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(task.reload.title).to eq("Draft the page")

    delete "/api/v1/tasks/#{task.id}", headers: headers_for(creator)
    expect(response).to have_http_status(:unprocessable_entity)
    expect(Task.exists?(task.id)).to be(true)

    task.update!(status: Task::STATUS_PENDING)
    project.update_columns(ends_on: Date.current - 1)
    patch "/api/v1/tasks/#{task.id}",
          params: { title: "Too late" },
          headers: headers_for(creator),
          as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body.dig("error", "code")).to eq("lifecycle_action_denied")
  end

  it "rejects edits and deletes from a teammate who is not the creator" do
    creator = create_onboarded_adult(email: "edit-team-c-#{SecureRandom.hex(3)}@example.com")
    joiner = create_onboarded_adult(email: "edit-team-j-#{SecureRandom.hex(3)}@example.com")
    project = Projects::CreateDraft.call(
      user: creator,
      workspace: creator.personal_workspace,
      title: "Team edits",
      mode: Project::MODE_TEAM,
      joining_mode: Project::JOINING_INSTANT,
      capacity: 3,
      roles_needed: [ "Designer" ]
    )
    project.update!(
      ends_on: Date.current + 30,
      proposed_tasks: [ { "title" => "Shared task", "summary" => "Do it" } ]
    )
    Projects::Confirm.call(project: project, user: creator)
    Projects::InstantJoin.call(project: project.reload, user: joiner, participant_role: "Designer")
    task = project.tasks.first

    patch "/api/v1/tasks/#{task.id}",
          params: { title: "Taken" },
          headers: headers_for(joiner),
          as: :json
    expect(response).to have_http_status(:forbidden)

    delete "/api/v1/tasks/#{task.id}", headers: headers_for(joiner)
    expect(response).to have_http_status(:forbidden)
    expect(task.reload.title).to eq("Shared task")
  end
end
