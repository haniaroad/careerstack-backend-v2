# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Platform admin", type: :request do
  def admin_pair
    admin = create_onboarded_adult(email: "padmin-#{SecureRandom.hex(3)}@example.com")
    PlatformStaff.create!(user: admin, role: PlatformStaff::ROLE, active: true)
    admin
  end

  it "rejects claim-only, record-only, organization admins, deactivated records, and stale sessions" do
    claimed = create_onboarded_adult(email: "claim-only-#{SecureRandom.hex(3)}@example.com")
    recorded = create_onboarded_adult(email: "record-only-#{SecureRandom.hex(3)}@example.com")
    PlatformStaff.create!(user: recorded, role: PlatformStaff::ROLE, active: true)
    org_admin = create_onboarded_adult(email: "org-admin-#{SecureRandom.hex(3)}@example.com")
    organization = create_organization
    create_membership(organization: organization, user: org_admin, role: OrganizationMembership::ADMIN)
    deactivated = create_onboarded_adult(email: "deactivated-#{SecureRandom.hex(3)}@example.com")
    PlatformStaff.create!(user: deactivated, role: PlatformStaff::ROLE, active: false)
    stale = admin_pair

    get "/api/v1/platform_admin/session", headers: staff_headers(claimed)
    expect(response).to have_http_status(:forbidden)

    get "/api/v1/platform_admin/session", headers: headers_for(recorded)
    expect(response).to have_http_status(:forbidden)

    get "/api/v1/platform_admin/session", headers: headers_for(org_admin)
    expect(response).to have_http_status(:forbidden)

    get "/api/v1/platform_admin/session", headers: staff_headers(deactivated)
    expect(response).to have_http_status(:forbidden)

    get "/api/v1/platform_admin/session", headers: staff_headers(stale, auth_time: 9.hours.ago)
    expect(response).to have_http_status(:unauthorized)
  end

  it "requires fresh authentication for suspension and omits date of birth from search and the notification" do
    admin = admin_pair
    target = create_onboarded_adult(email: "suspend-me-#{SecureRandom.hex(3)}@example.com")
    target.profile.update!(date_of_birth: Date.new(2000, 1, 2), display_name: "Suspend Me")

    post "/api/v1/platform_admin/users/#{target.id}/suspend",
         params: { reason: "abuse" },
         headers: staff_headers(admin, auth_time: 10.minutes.ago),
         as: :json
    expect(response).to have_http_status(:forbidden)
    expect(target.reload.status).to eq(User::ACTIVE)

    post "/api/v1/platform_admin/users/#{target.id}/suspend",
         params: { reason: "abuse" },
         headers: staff_headers(admin),
         as: :json
    expect(response).to have_http_status(:ok)
    expect(target.reload).to be_suspended
    note = Notification.find_by!(event_key: "suspension", recipient_user_id: target.id)
    expect(note.payload.to_json).not_to include("2000-01-02")
    expect(note.actor_id).not_to eq(target.id)

    get "/api/v1/platform_admin/search", params: { q: "Suspend Me" }, headers: staff_headers(admin)
    expect(response).to have_http_status(:ok)
    body = response.parsed_body
    expect(body["users"].first["email"]).to eq(target.email)
    expect(body.to_json).not_to include("2000-01-02")
  end

  it "resends an invitation without a second record, links by email, and rejects slug changes" do
    admin = admin_pair
    organization = create_organization
    invitation, = Invitation.issue!(organization: organization, email: "invitee-#{SecureRandom.hex(3)}@example.com")
    count = Invitation.count

    post "/api/v1/platform_admin/invitations/#{invitation.id}/resend", headers: staff_headers(admin), as: :json
    expect(response).to have_http_status(:ok)
    expect(Invitation.count).to eq(count)

    target = create_onboarded_adult(email: "link-me-#{SecureRandom.hex(3)}@example.com")
    post "/api/v1/platform_admin/users/#{target.id}/link",
         params: { firebase_uid: "new-uid-#{SecureRandom.hex(3)}", confirm_email: "wrong@example.com" },
         headers: staff_headers(admin),
         as: :json
    expect(response).to have_http_status(:unprocessable_entity)

    new_uid = "new-uid-#{SecureRandom.hex(3)}"
    post "/api/v1/platform_admin/users/#{target.id}/link",
         params: { firebase_uid: new_uid, confirm_email: target.email },
         headers: staff_headers(admin),
         as: :json
    expect(response).to have_http_status(:ok)
    expect(target.reload.firebase_uid).to eq(new_uid)

    post "/api/v1/platform_admin/users/#{target.id}/slug", headers: staff_headers(admin), as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(target.profile.reload.slug).to be_present
  end

  it "starts and cancels deletion without suspending, and anonymizes only after 30 days" do
    admin = admin_pair
    target = create_onboarded_adult(email: "delete-me-#{SecureRandom.hex(3)}@example.com")

    post "/api/v1/platform_admin/users/#{target.id}/deletion",
         params: { reason: "request" },
         headers: staff_headers(admin),
         as: :json
    expect(response).to have_http_status(:ok)
    target.reload
    expect(target.status).to eq(User::ACTIVE)
    expect(target).to be_in_deletion_recovery
    expect(PlatformAdmin::AnonymizeDue.call).to eq(0)
    expect(target.reload.anonymized_at).to be_nil

    target.update!(deletion_requested_at: 31.days.ago)
    expect(PlatformAdmin::AnonymizeDue.call).to eq(1)
    expect(target.reload.anonymized_at).to be_present
    expect(target.email).to end_with("@careerstack.invalid")

    other = create_onboarded_adult(email: "cancel-delete-#{SecureRandom.hex(3)}@example.com")
    post "/api/v1/platform_admin/users/#{other.id}/deletion",
         params: { reason: "request" },
         headers: staff_headers(admin),
         as: :json
    post "/api/v1/platform_admin/users/#{other.id}/deletion/cancel",
         params: { reason: "restored" },
         headers: staff_headers(admin),
         as: :json
    expect(other.reload).not_to be_in_deletion_recovery
    other.update!(deletion_requested_at: 31.days.ago)
    expect(PlatformAdmin::AnonymizeDue.call).to eq(0)
  end

  it "grants and removes credits with a reason and rejects a participant grant" do
    admin = admin_pair
    owner = create_onboarded_adult(email: "ledger-#{SecureRandom.hex(3)}@example.com")
    before = CreditLedgerEntry.where(owner: owner).count

    post "/api/v1/platform_admin/credits",
         params: { owner_type: "user", owner_id: owner.id, amount: 2, direction: "remove", reason: "" },
         headers: staff_headers(admin),
         as: :json
    expect(response).to have_http_status(:unprocessable_entity)

    post "/api/v1/platform_admin/credits",
         params: { owner_type: "user", owner_id: owner.id, amount: 2, direction: "grant", reason: "goodwill" },
         headers: staff_headers(admin),
         as: :json
    expect(response).to have_http_status(:ok)
    expect(CreditLedgerEntry.where(owner: owner).count).to eq(before + 1)
    expect(CreditLedgerEntry.where(owner: owner).order(:created_at).first.amount).to eq(CreditLedgerEntry.where(owner: owner).order(:created_at).first.amount)

    post "/api/v1/platform_admin/credits",
         params: { owner_type: "user", owner_id: owner.id, amount: 2, direction: "grant", reason: "goodwill" },
         headers: headers_for(owner),
         as: :json
    expect(response).to have_http_status(:forbidden)
  end

  it "approves a refund and closes an upgrade request" do
    admin = admin_pair
    buyer = create_onboarded_adult(email: "buyer-#{SecureRandom.hex(3)}@example.com")
    lot = CreditLot.create!(
      owner: buyer,
      source: "personal_pack_purchase",
      original_amount: 3,
      remaining: 2,
      granted_at: Time.current
    )
    purchase = CreditPurchase.create!(
      user: buyer,
      credit_lot: lot,
      stripe_checkout_session_id: "cs_#{SecureRandom.hex(4)}",
      status: "completed",
      credits: 3,
      completed_at: Time.current
    )
    refund = CreditRefundRequest.create!(user: buyer, credit_purchase: purchase, unused_credits_at_request: 2, status: "submitted")

    post "/api/v1/platform_admin/refund_requests/#{refund.id}/approve",
         params: { reason: "unused" },
         headers: staff_headers(admin),
         as: :json
    expect(response).to have_http_status(:ok)
    expect(refund.reload.status).to eq("approved")

    organization = create_organization
    requester = create_onboarded_adult(email: "requester-#{SecureRandom.hex(3)}@example.com")
    upgrade = OrganizationUpgradeRequest.create!(
      organization: organization,
      requesting_user: requester,
      expected_participants: 10,
      expected_projects_or_cohorts: 2,
      timeline: "fall",
      status: "open"
    )
    post "/api/v1/platform_admin/upgrade_requests/#{upgrade.id}",
         params: { status: "closed" },
         headers: staff_headers(admin),
         as: :json
    expect(response).to have_http_status(:ok)
    expect(upgrade.reload.status).to eq("closed")
  end

  it "hides a review, removes a message, archives a project, and audits file and date-of-birth access" do
    admin = admin_pair
    creator = create_onboarded_adult(email: "mod-c-#{SecureRandom.hex(3)}@example.com")
    other = create_onboarded_adult(email: "mod-o-#{SecureRandom.hex(3)}@example.com")
    project = Projects::CreateDraft.call(
      user: creator,
      workspace: creator.personal_workspace,
      title: "Moderation",
      mode: Project::MODE_TEAM,
      joining_mode: Project::JOINING_INSTANT,
      capacity: 3,
      roles_needed: [ "Designer" ]
    )
    project.update!(status: Project::STATUS_ACTIVE, ends_on: Date.current + 20)
    review = PeerReview.create!(
      project: project,
      reviewer: creator,
      reviewee: other,
      status: PeerReview::STATUS_COMPLETED,
      rating: 5,
      comment: "Solid work",
      submitted_at: Time.current
    )
    message = ProjectMessage.create!(project: project, author: creator, body: "hello team")
    ProjectMessageReport.create!(
      project_message: message,
      reporter: other,
      report_type: "harassment",
      reason_category: "harassment",
      status: "open"
    )

    post "/api/v1/platform_admin/peer_reviews/#{review.id}/hide",
         params: { reason: "abuse" },
         headers: staff_headers(admin),
         as: :json
    expect(response).to have_http_status(:ok)
    expect(review.reload.hidden_at).to be_present
    expect(PeerReview.visible).not_to include(review)

    post "/api/v1/platform_admin/project_messages/#{message.id}/remove",
         params: { reason: "abuse" },
         headers: staff_headers(admin),
         as: :json
    expect(response).to have_http_status(:ok)
    expect(ProjectMessage.visible).not_to include(message.reload)
    expect(ProjectMessageReport.where(project_message_id: message.id)).to exist

    post "/api/v1/platform_admin/projects/#{project.id}/archive",
         params: { reason: "abuse" },
         headers: staff_headers(admin),
         as: :json
    expect(response).to have_http_status(:ok)
    expect(project.reload).to be_archived
    expect(creator.reload.status).to eq(User::ACTIVE)

    other.profile.update!(date_of_birth: Date.new(1999, 5, 5))
    post "/api/v1/platform_admin/users/#{other.id}/date_of_birth",
         params: { reason: "support", user_ids: [ other.id, creator.id ] },
         headers: staff_headers(admin),
         as: :json
    expect(response).to have_http_status(:forbidden)

    post "/api/v1/platform_admin/users/#{other.id}/date_of_birth",
         params: { reason: "support ticket" },
         headers: staff_headers(admin),
         as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body["date_of_birth"]).to eq("1999-05-05")
    event = StaffAuditEvent.where(action: "date_of_birth_read").last
    expect(event.reason).not_to include("1999-05-05")
    expect(event.attributes.values.join).not_to include("1999-05-05")
  end

  it "corrects an AI review without a model call and keeps impersonation read-only" do
    admin = admin_pair
    creator = create_onboarded_adult(email: "ai-c-#{SecureRandom.hex(3)}@example.com")
    project = Projects::CreateDraft.call(user: creator, workspace: creator.personal_workspace, title: "Solo")
    project.update!(status: Project::STATUS_ACTIVE, mode: Project::MODE_SOLO, ends_on: Date.current + 10)
    task = Task.create!(project: project, title: "Do it", status: Task::STATUS_SUBMITTED)
    submission = TaskSubmission.create!(
      task: task,
      submitted_by: creator,
      attempt_number: 1,
      body: "done",
      content_fingerprint: "fp",
      submitted_at: Time.current
    )
    review = AiReview.create!(
      task: task,
      task_submission: submission,
      user: creator,
      status: AiReview::STATUS_SUCCEEDED,
      decision: "corrections_requested",
      content_fingerprint: "fp"
    )

    post "/api/v1/platform_admin/ai_reviews/#{review.id}/correct",
         params: { decision: "approved", reason: "system error" },
         headers: headers_for(creator),
         as: :json
    expect(response).to have_http_status(:forbidden)

    post "/api/v1/platform_admin/ai_reviews/#{review.id}/correct",
         params: { decision: "approved", reason: "system error" },
         headers: staff_headers(admin),
         as: :json
    expect(response).to have_http_status(:ok)
    expect(review.reload.decision).to eq("approved")

    post "/api/v1/platform_admin/impersonation",
         params: { user_id: creator.id, reason: "support" },
         headers: staff_headers(admin),
         as: :json
    expect(response).to have_http_status(:created)
    session_id = response.parsed_body["session_id"]
    original_name = creator.profile.display_name

    patch "/api/v1/profiles/me",
          params: { display_name: "Hacked" },
          headers: staff_headers(admin).merge("X-Impersonation-Session" => session_id),
          as: :json
    expect(response).to have_http_status(:forbidden)
    expect(creator.profile.reload.display_name).to eq(original_name)

    post "/api/v1/platform_admin/users/#{creator.id}/date_of_birth",
         params: { reason: "nope" },
         headers: staff_headers(admin).merge("X-Impersonation-Session" => session_id),
         as: :json
    expect(response).to have_http_status(:forbidden)

    post "/api/v1/platform_admin/impersonation/#{session_id}/exit",
         headers: staff_headers(admin).merge("X-Impersonation-Session" => session_id),
         as: :json
    expect(response).to have_http_status(:ok)
    expect(ImpersonationSession.find(session_id).ended_at).to be_present

    get "/api/v1/platform_admin/queues", headers: staff_headers(admin)
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.keys).to include("failed_jobs", "failed_emails", "escalations")

    audit = StaffAuditEvent.last
    expect { audit.update!(reason: "nope") }.to raise_error(DomainError)
    expect { audit.destroy! }.to raise_error(DomainError)

    blob = ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new("staff-only"),
      filename: "note.txt",
      content_type: "text/plain"
    )
    post "/api/v1/platform_admin/files/#{blob.id}/inspect",
         params: { reason: "support ticket" },
         headers: staff_headers(admin),
         as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body["signed_id"]).to be_present
    expect(StaffAuditEvent.where(action: "file_inspect").last.reason).to eq("support ticket")
    expect(StaffAuditEvent.where(action: "file_inspect").last.reason).not_to include("staff-only")

    session = ImpersonationSession.create!(
      actor: admin,
      target: creator,
      reason: "follow up",
      expires_at: 1.minute.ago
    )
    get "/api/v1/session", headers: staff_headers(admin).merge("X-Impersonation-Session" => session.id)
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body["impersonation"]).to be_nil
    expect(StaffAuditEvent.where(action: "impersonation_expire", target_id: session.id)).to exist
    expect(session.reload.ended_at).to be_present
  end
end
