# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Notifications API", type: :request do
  def create_in_app_notification!(user:, event_key: "welcome", read_at: nil)
    meta = Notifications::Catalog.event!(event_key)
    copy = Notifications::Catalog.copy_for(event_key)
    Notification.create!(
      recipient_user: user,
      recipient_email: user.email,
      event_key: event_key,
      tier: meta[:tier],
      source_type: "User",
      source_id: SecureRandom.uuid,
      payload: {
        "title" => copy[:title],
        "heading" => copy[:heading],
        "body" => copy[:body],
        "path" => copy[:path],
        "cta" => copy[:cta]
      },
      read_at: read_at,
      email_status: "skipped"
    )
  end

  it "rejects unauthenticated access" do
    get "/api/v1/notifications"
    expect(response).to have_http_status(:unauthorized)

    get "/api/v1/notification_preferences"
    expect(response).to have_http_status(:unauthorized)
  end

  it "lists own notifications and unread count" do
    owner = create_onboarded_adult(email: "n-owner@example.com")
    other = create_onboarded_adult(email: "n-other@example.com")
    mine = create_in_app_notification!(user: owner)
    create_in_app_notification!(user: other)

    get "/api/v1/notifications", headers: headers_for(owner)
    expect(response).to have_http_status(:ok)
    ids = response.parsed_body["notifications"].map { |row| row["id"] }
    expect(ids).to eq([ mine.id ])

    get "/api/v1/notifications/unread_count", headers: headers_for(owner)
    expect(response.parsed_body["unread_count"]).to eq(1)
  end

  it "marks one notification read and rejects IDOR" do
    owner = create_onboarded_adult(email: "n-read@example.com")
    other = create_onboarded_adult(email: "n-idor@example.com")
    mine = create_in_app_notification!(user: owner)
    theirs = create_in_app_notification!(user: other)

    post "/api/v1/notifications/#{theirs.id}/read", headers: headers_for(owner)
    expect(response).to have_http_status(:not_found)
    expect(theirs.reload.read_at).to be_nil

    post "/api/v1/notifications/#{mine.id}/read", headers: headers_for(owner)
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig("notification", "read")).to be(true)
    expect(mine.reload.read_at).to be_present
  end

  it "marks all unread notifications read" do
    owner = create_onboarded_adult(email: "n-all@example.com")
    create_in_app_notification!(user: owner)
    create_in_app_notification!(user: owner)

    post "/api/v1/notifications/read_all", headers: headers_for(owner)
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body["unread_count"]).to eq(0)
    expect(Notification.for_user(owner).unread).to be_empty
  end

  it "returns preference defaults and rejects disabling mandatory categories" do
    user = create_onboarded_adult(email: "n-pref@example.com")

    get "/api/v1/notification_preferences", headers: headers_for(user)
    expect(response).to have_http_status(:ok)
    ids = response.parsed_body["preferences"].map { |row| row["id"] }
    expect(ids).to eq(%w[account project_activity reminders])
    account = response.parsed_body["preferences"].find { |row| row["id"] == "account" }
    expect(account["can_disable"]).to be(false)
    expect(account["email_enabled"]).to be(true)

    put "/api/v1/notification_preferences",
        params: { preferences: [ { id: "account", email_enabled: false } ] },
        headers: headers_for(user),
        as: :json
    expect(response).to have_http_status(:unprocessable_entity)

    put "/api/v1/notification_preferences",
        params: { preferences: [ { id: "project_activity", email_enabled: false } ] },
        headers: headers_for(user),
        as: :json
    expect(response).to have_http_status(:ok)
    row = response.parsed_body["preferences"].find { |item| item["id"] == "project_activity" }
    expect(row["email_enabled"]).to be(false)
  end

  it "allows the owner to update timezone on their profile and session, never on public profiles" do
    user = create_onboarded_adult(email: "tz-api@example.com")

    patch "/api/v1/profiles/me",
          params: { timezone: "America/New_York" },
          headers: headers_for(user),
          as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body["profile"]).not_to have_key("timezone")
    expect(user.reload.timezone).to eq("America/New_York")

    get "/api/v1/session", headers: headers_for(user)
    expect(response.parsed_body.dig("user", "timezone")).to eq("America/New_York")

    get "/api/v1/profiles/#{user.profile.slug}", headers: headers_for(user)
    expect(response.parsed_body.fetch("profile")).not_to have_key("timezone")
    expect(JSON.generate(response.parsed_body)).not_to include("America/New_York")
  end
end
