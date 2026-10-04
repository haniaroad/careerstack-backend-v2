# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Task submission files", type: :request do
  def personal_team!(creator:)
    project = Projects::CreateDraft.call(
      user: creator,
      workspace: creator.personal_workspace,
      title: "File review team",
      mode: Project::MODE_TEAM,
      joining_mode: Project::JOINING_INSTANT,
      capacity: 3,
      roles_needed: [ "Designer" ]
    )
    project.update!(
      ends_on: Date.current + 30,
      proposed_tasks: [
        { "title" => "Open task", "summary" => "Claim me", "recommended_due_date" => (Date.current + 4).iso8601 }
      ]
    )
    Projects::Confirm.call(project: project, user: creator)
    project.reload
  end

  it "lets the creator open a submission file without an authorization header" do
    creator = create_onboarded_adult(email: "file-creator-#{SecureRandom.hex(3)}@example.com")
    member = create_onboarded_adult(email: "file-member-#{SecureRandom.hex(3)}@example.com")
    project = personal_team!(creator: creator)
    Projects::InstantJoin.call(project: project, user: member, participant_role: "Designer")
    task = project.tasks.first

    patch "/api/v1/tasks/#{task.id}/assignment",
          params: { assignee_id: member.id }.to_json,
          headers: headers_for(member).merge("CONTENT_TYPE" => "application/json")
    expect(response).to have_http_status(:ok)

    blob = ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new("hello evidence"),
      filename: "evidence.txt",
      content_type: "text/plain"
    )
    post "/api/v1/tasks/#{task.id}/submissions",
         params: { body: "See the file", signed_blob_ids: [ blob.signed_id ] }.to_json,
         headers: headers_for(member).merge("CONTENT_TYPE" => "application/json")
    expect(response).to have_http_status(:created)

    get "/api/v1/tasks/#{task.id}", headers: headers_for(creator)
    expect(response).to have_http_status(:ok)
    file = response.parsed_body.dig("task", "submissions", 0, "files", 0)
    expect(file["filename"]).to eq("evidence.txt")
    expect(file["url"]).to include("/rails/active_storage/")
    expect(file["url"]).to include("evidence.txt")

    get URI.parse(file["url"]).path
    expect(response).to have_http_status(:redirect)
    follow_redirect!
    expect(response.body).to eq("hello evidence")
  end
end
