# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Project messaging", type: :request do
  def grant_credits!(owner:, amount:, actor:)
    source = owner.is_a?(Organization) ? "organization_contract" : "personal_pack_purchase"
    lot = CreditLot.create!(
      owner: owner,
      source: source,
      original_amount: amount,
      remaining: amount,
      stripe_payment_ref: owner.is_a?(Organization) ? nil : "pi_test_#{SecureRandom.hex(4)}",
      granted_at: Time.current
    )
    CreditLedgerEntry.create!(
      owner: owner,
      event: "grant",
      amount: amount,
      actor_user: actor,
      reason: source,
      idempotency_key: "topup-#{SecureRandom.hex(4)}",
      credit_lot: lot
    )
  end

  def active_team!
    creator = create_onboarded_adult(email: "msg-c-#{SecureRandom.hex(3)}@example.com")
    participant = create_onboarded_adult(email: "msg-p-#{SecureRandom.hex(3)}@example.com")
    outsider = create_onboarded_adult(email: "msg-o-#{SecureRandom.hex(3)}@example.com")
    grant_credits!(owner: creator, amount: 5, actor: creator)
    project = Projects::CreateDraft.call(
      user: creator,
      workspace: creator.personal_workspace,
      title: "Message team",
      mode: Project::MODE_TEAM,
      joining_mode: Project::JOINING_INSTANT,
      capacity: 3,
      roles_needed: [ "Designer" ]
    )
    project.update!(
      ends_on: Date.current + 30,
      skills: [ "Facilitation" ],
      proposed_tasks: [ { "title" => "One", "summary" => "x", "recommended_due_date" => (Date.current + 5).iso8601, "submission_expectations" => "Text" } ]
    )
    Projects::Confirm.call(project: project, user: creator)
    ProjectMembership.create!(
      project: project.reload,
      user: participant,
      role: ProjectMembership::ROLE_PARTICIPANT,
      status: ProjectMembership::STATUS_ACTIVE,
      participant_role: "Designer",
      join_source: ProjectMembership::JOIN_SOURCE_INSTANT
    )
    {
      creator: creator,
      participant: participant,
      outsider: outsider,
      project: project.reload
    }
  end

  def active_solo!(user)
    grant_credits!(owner: user, amount: 3, actor: user)
    project = Projects::CreateDraft.call(
      user: user,
      workspace: user.personal_workspace,
      title: "Solo quiet"
    )
    project.update!(
      ends_on: Date.current + 30,
      skills: [ "Facilitation" ],
      proposed_tasks: [ { "title" => "One", "summary" => "x", "recommended_due_date" => (Date.current + 5).iso8601, "submission_expectations" => "Text" } ]
    )
    Projects::Confirm.call(project: project, user: user)
    project.reload
  end

  it "lets active members post and list messages and notifies other members without quoting bodies" do
    ctx = active_team!

    post "/api/v1/projects/#{ctx[:project].id}/messages",
         params: { body: "Hello team — see https://example.com" },
         headers: headers_for(ctx[:creator]),
         as: :json
    expect(response).to have_http_status(:created)
    expect(response.parsed_body["message"]["body"]).to include("Hello team")

    get "/api/v1/projects/#{ctx[:project].id}/messages", headers: headers_for(ctx[:participant])
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body["messages"].length).to eq(1)
    expect(response.parsed_body["unread"]).to be(true)

    note = Notification.find_by!(event_key: "unread_project_messages", recipient_user: ctx[:participant])
    expect(note.payload["body"]).not_to include("Hello team")
    expect(note.payload["path"]).to eq("/projects/#{ctx[:project].id}")
    expect(Notification.where(event_key: "unread_project_messages", recipient_user: ctx[:creator])).to be_empty
  end

  it "rejects solo projects, non-members, empty bodies, and unauthenticated access" do
    ctx = active_team!
    solo_owner = create_onboarded_adult(email: "msg-solo-#{SecureRandom.hex(3)}@example.com")
    solo = active_solo!(solo_owner)

    post "/api/v1/projects/#{solo.id}/messages",
         params: { body: "Nope" },
         headers: headers_for(solo_owner),
         as: :json
    expect(response).to have_http_status(:not_found)

    get "/api/v1/projects/#{ctx[:project].id}/messages", headers: headers_for(ctx[:outsider])
    expect(response).to have_http_status(:not_found)

    post "/api/v1/projects/#{ctx[:project].id}/messages",
         params: { body: "   " },
         headers: headers_for(ctx[:creator]),
         as: :json
    expect(response).to have_http_status(:unprocessable_entity)

    get "/api/v1/projects/#{ctx[:project].id}/messages"
    expect(response).to have_http_status(:unauthorized)
  end

  it "revokes access after leave and clears unread when the thread is marked read" do
    ctx = active_team!
    message = ProjectMessage.create!(project: ctx[:project], author: ctx[:creator], body: "Please read")

    post "/api/v1/projects/#{ctx[:project].id}/messages/read",
         headers: headers_for(ctx[:participant]),
         as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body["unread"]).to be(false)

    get "/api/v1/projects/#{ctx[:project].id}/messages", headers: headers_for(ctx[:participant])
    expect(response.parsed_body["unread"]).to be(false)

    Projects::Leave.call(
      project: ctx[:project],
      user: ctx[:participant],
      reason_category: "personal_reason",
      reason_detail: nil
    )

    get "/api/v1/projects/#{ctx[:project].id}/messages", headers: headers_for(ctx[:participant])
    expect(response).to have_http_status(:not_found)

    get "/api/v1/projects/#{ctx[:project].id}/messages", headers: headers_for(ctx[:creator])
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body["messages"].map { |row| row["id"] }).to include(message.id)
  end

  it "accepts message reports from other members and rejects self-reports" do
    ctx = active_team!
    message = ProjectMessage.create!(project: ctx[:project], author: ctx[:creator], body: "Report me")

    post "/api/v1/project_messages/#{message.id}/reports",
         params: { report_type: "inappropriate", reason_category: "harassment", details: "unwanted" },
         headers: headers_for(ctx[:participant]),
         as: :json
    expect(response).to have_http_status(:created)
    expect(ProjectMessageReport.where(project_message: message, reporter: ctx[:participant]).count).to eq(1)

    post "/api/v1/project_messages/#{message.id}/reports",
         params: { report_type: "inappropriate", reason_category: "harassment" },
         headers: headers_for(ctx[:creator]),
         as: :json
    expect(response).to have_http_status(:forbidden)

    post "/api/v1/project_messages/#{message.id}/reports",
         params: { report_type: "inappropriate", reason_category: "harassment" },
         as: :json
    expect(response).to have_http_status(:unauthorized)
  end
end
