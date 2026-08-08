# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Inbox and creator review API", type: :request do
  def grant_credits!(owner:, amount:, actor:)
    source = owner.is_a?(Organization) ? "organization_contract" : "personal_pack_purchase"
    ref = owner.is_a?(Organization) ? nil : "pi_test_#{SecureRandom.hex(4)}"
    lot = CreditLot.create!(
      owner: owner,
      source: source,
      original_amount: amount,
      remaining: amount,
      stripe_payment_ref: ref,
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

  def setup_team_submission!
    creator = create_onboarded_adult(email: "inbox-creator-#{SecureRandom.hex(3)}@example.com")
    participant = create_onboarded_adult(email: "inbox-assignee-#{SecureRandom.hex(3)}@example.com")
    organization = create_organization(name: "Inbox Org #{SecureRandom.hex(3)}")
    create_membership(organization: organization, user: creator, role: OrganizationMembership::ADMIN)
    create_membership(organization: organization, user: participant, role: OrganizationMembership::PARTICIPANT)
    Credits::GrantOrganizationTrial.call(user: creator, organization: organization)
    grant_credits!(owner: organization, amount: 5, actor: creator)

    workspace = organization.workspace
    creator.update!(active_workspace: workspace)
    participant.update!(active_workspace: workspace)

    project = Projects::CreateDraft.call(
      user: creator,
      workspace: workspace,
      title: "Inbox team",
      mode: Project::MODE_TEAM,
      joining_mode: Project::JOINING_INSTANT,
      capacity: 3,
      roles_needed: [ "Designer" ]
    )
    project.update!(
      proposed_tasks: [
        {
          "title" => "Ship mock",
          "summary" => "Design",
          "recommended_due_date" => (Date.current + 7).iso8601,
          "submission_expectations" => "PNG"
        }
      ]
    )
    Projects::Confirm.call(project: project, user: creator)
    Projects::InstantJoin.call(project: project.reload, user: participant, participant_role: "Designer")
    task = project.reload.tasks.first
    Tasks::Assign.call(task: task, actor: creator, assignee: participant)
    Tasks::Submit.call(task: task.reload, user: participant, body: "Done", links: [], signed_blob_ids: [])

    {
      creator: creator.reload,
      participant: participant.reload,
      project: project.reload,
      task: task.reload,
      headers: headers_for(creator).merge("CONTENT_TYPE" => "application/json"),
      participant_headers: headers_for(participant).merge("CONTENT_TYPE" => "application/json")
    }
  end

  it "lists task reviews for the creator and excludes non-creators from that queue" do
    ctx = setup_team_submission!

    get "/api/v1/inbox/items", params: { category: "task_review" }, headers: ctx[:headers]

    expect(response).to have_http_status(:ok)
    items = JSON.parse(response.body).fetch("items")
    expect(items.map { |i| i["related_id"] }).to include(ctx[:task].id)
    expect(items.first["category"]).to eq("task_review")

    get "/api/v1/inbox/items", params: { category: "task_review" }, headers: ctx[:participant_headers]
    expect(JSON.parse(response.body).fetch("items")).to be_empty
  end

  it "lets the creator approve via creator_review and forbids participants" do
    ctx = setup_team_submission!

    post "/api/v1/tasks/#{ctx[:task].id}/creator_review",
         params: { decision: "approved", feedback: "Nice work" }.to_json,
         headers: ctx[:participant_headers]
    expect(response).to have_http_status(:forbidden)

    post "/api/v1/tasks/#{ctx[:task].id}/creator_review",
         params: { decision: "approved", feedback: "Nice work" }.to_json,
         headers: ctx[:headers]
    expect(response).to have_http_status(:ok)
    body = JSON.parse(response.body)
    expect(body.dig("task", "status")).to eq("approved")
    expect(body.dig("task", "creator_review_decision")).to eq("approved")
  end

  it "isolates inbox items by workspace" do
    ctx = setup_team_submission!
    other = create_onboarded_adult(email: "other-ws-#{SecureRandom.hex(3)}@example.com")

    get "/api/v1/inbox/items", headers: headers_for(other)
    expect(response).to have_http_status(:ok)
    expect(JSON.parse(response.body).fetch("items")).to be_empty

    get "/api/v1/inbox/items", headers: ctx[:headers]
    expect(JSON.parse(response.body).fetch("items").size).to be >= 1
  end
end
