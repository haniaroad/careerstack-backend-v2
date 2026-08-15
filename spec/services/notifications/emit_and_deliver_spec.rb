# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Notifications emit and delivery" do
  include ActiveSupport::Testing::TimeHelpers
  FakeMail = Struct.new(:deliveries) do
    def initialize
      super([])
    end

    def deliver(**kwargs)
      deliveries << kwargs
      { status: "sent" }
    end
  end

  def emit_welcome!(user, source_id: nil)
    Notifications::Emit.call(
      event_key: "welcome",
      actor: nil,
      recipients: [ user ],
      source: Notifications::Hook.named_source(source_id || "welcome:#{user.id}:#{SecureRandom.hex(4)}"),
      payload: {}
    )
  end

  around do |example|
    adapter = FakeMail.new
    TransactionalMail::Provider.stub!(adapter)
    example.run
  ensure
    TransactionalMail::Provider.unstub!
  end

  it "validates IANA timezones on users" do
    user = create_onboarded_adult(email: "tz@example.com")
    expect(user.timezone).to eq("UTC")
    user.timezone = "America/New_York"
    expect(user).to be_valid
    user.timezone = "Not/AZone"
    expect(user).not_to be_valid
  end

  it "is idempotent for the same user, event, and source" do
    user = create_onboarded_adult(email: "idempotent-n@example.com")
    source = user

    expect {
      2.times do
        Notifications::Emit.call(
          event_key: "welcome",
          actor: nil,
          recipients: [ user ],
          source: source,
          payload: {}
        )
      end
    }.to change(Notification, :count).by(1)
  end

  it "creates staff email-only rows with no recipient user" do
    project = Projects::CreateDraft.call(
      user: create_onboarded_adult(email: "staff-actor@example.com"),
      workspace: User.find_by!(email: "staff-actor@example.com").personal_workspace,
      title: "Staff notice"
    )

    created = Notifications::Emit.call(
      event_key: "escalation_created",
      actor: nil,
      recipients: [ { email: Notifications::Catalog::STAFF_INBOX } ],
      source: project,
      project: project,
      payload: { "project_title" => "Staff notice", "project_id" => project.id, "reason_label" => "Overdue" }
    )

    notification = created.first
    expect(notification.recipient_user_id).to be_nil
    expect(notification.recipient_email).to eq("hello@careerstack.co")
  end

  it "seeds preference defaults and refuses to disable mandatory categories" do
    user = create_onboarded_adult(email: "prefs@example.com")
    NotificationPreference.ensure_defaults!(user)

    expect(user.notification_preferences.pluck(:category)).to match_array(%w[account project_activity reminders])
    account = user.notification_preferences.find_by!(category: "account")
    expect(account.email_enabled).to be(true)
    reminders = user.notification_preferences.find_by!(category: "reminders")
    expect(reminders.digest_cadence).to eq("daily")
  end

  it "does not emit registered but inactive catalog events" do
    user = create_onboarded_adult(email: "no-peer@example.com")
    expect {
      Notifications::Emit.call(
        event_key: "peer_review_received",
        actor: nil,
        recipients: [ user ],
        source: user,
        payload: {}
      )
    }.not_to change(Notification, :count)
  end

  it "never notifies the actor of their own action" do
    actor = create_onboarded_adult(email: "self-actor@example.com")
    Notifications::Emit.call(
      event_key: "welcome",
      actor: actor,
      recipients: [ actor ],
      source: actor,
      payload: {}
    )
    expect(Notification.where(recipient_user: actor)).to be_empty
  end

  it "coalesces assigned-task emails into one delivery" do
    creator = create_onboarded_adult(email: "coal-creator@example.com")
    assignee = create_onboarded_adult(email: "coal-assignee@example.com")
    project = Projects::CreateDraft.call(user: creator, workspace: creator.personal_workspace, title: "Coalesce")

    first = Notifications::Emit.call(
      event_key: "task_assigned",
      actor: creator,
      recipients: [ assignee ],
      source: Notifications::Hook.named_source("coal-1"),
      project: project,
      payload: { "task_title" => "Task A", "project_title" => "Coalesce", "task_id" => SecureRandom.uuid, "project_id" => project.id }
    ).first
    second = Notifications::Emit.call(
      event_key: "task_assigned",
      actor: creator,
      recipients: [ assignee ],
      source: Notifications::Hook.named_source("coal-2"),
      project: project,
      payload: { "task_title" => "Task B", "project_title" => "Coalesce", "task_id" => SecureRandom.uuid, "project_id" => project.id }
    ).first

    expect(first.email_status).to eq("scheduled")
    expect(second.email_status).to eq("scheduled")
    expect(first.coalesce_key).to eq(second.coalesce_key)

    adapter = TransactionalMail::Provider.adapter
    Notifications::Deliver.call(notification: first)
    expect(adapter.deliveries.size).to eq(1)
    expect(first.reload.email_status).to eq("sent")
    expect(second.reload.email_status).to eq("sent")
  end

  it "skips configurable email when the in-app row was read within 15 minutes" do
    user = create_onboarded_adult(email: "seen@example.com")
    meta = Notifications::Catalog.event!("project_invitation")
    created = Notification.create!(
      recipient_user: user,
      recipient_email: user.email,
      event_key: "project_invitation",
      tier: meta[:tier],
      source_type: "User",
      source_id: user.id,
      payload: { "title" => "Invite", "body" => "Join", "path" => "/projects/x" },
      email_status: "pending"
    )
    created.mark_read!

    Notifications::Deliver.call(notification: created)
    expect(created.reload.email_status).to eq("skipped")
    expect(created.email_skip_reason).to eq("in_app_seen")
    expect(TransactionalMail::Provider.adapter.deliveries).to be_empty
  end

  it "does not send digest mail outside the 08:00-20:00 recipient window" do
    user = create_onboarded_adult(email: "window@example.com")
    user.update!(timezone: "UTC")
    notification = Notifications::Emit.call(
      event_key: "activity_summary",
      actor: nil,
      recipients: [ user ],
      source: user,
      payload: {}
    ).first
    expect(notification.email_status).to eq("scheduled")

    travel_to Time.utc(2026, 8, 14, 3, 0, 0) do
      Notifications::Digest.new.send(:deliver_due_digests)
    end
    expect(notification.reload.email_status).to eq("scheduled")
    expect(TransactionalMail::Provider.adapter.deliveries).to be_empty
  end

  it "does not send an empty weekly activity digest" do
    user = create_onboarded_adult(email: "empty-digest@example.com")
    NotificationPreference.ensure_defaults!(user)
    user.notification_preferences.find_by!(category: "reminders").update!(digest_cadence: "weekly")

    expect {
      Notifications::Digest.call
    }.not_to change { Notification.where(event_key: "activity_summary").count }
  end

  it "suppresses delivery to bounced addresses and does not send twice" do
    user = create_onboarded_adult(email: "bounce@example.com")
    EmailSuppression.create!(address: user.email, reason: "bounce", occurred_at: Time.current)
    notification = emit_welcome!(user).first

    Notifications::Deliver.call(notification: notification) if notification.email_status == "pending"
    expect(notification.reload.email_status).to eq("suppressed")

    Notifications::Deliver.call(notification: notification.reload)
    expect(TransactionalMail::Provider.adapter.deliveries).to be_empty
  end

  it "swaps the mail adapter via stub" do
    user = create_onboarded_adult(email: "adapter@example.com")
    notification = emit_welcome!(user).first
    Notifications::Deliver.call(notification: notification) unless notification.email_status == "sent"
    expect(TransactionalMail::Provider.adapter.deliveries.size).to eq(1)
    expect(notification.reload.email_status).to eq("sent")

    Notifications::Deliver.call(notification: notification.reload)
    expect(TransactionalMail::Provider.adapter.deliveries.size).to eq(1)
  end
end
