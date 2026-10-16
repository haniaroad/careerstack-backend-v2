# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Profile photos", type: :request do
  include IdentityFixtures
  include AuthHelpers

  let(:user) { create_onboarded_adult(email: "photo-owner@example.com") }

  def png_bytes
    Base64.decode64("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==")
  end

  def animated_gif_bytes
    require "vips"
    top = Vips::Image.black(8, 8)
    bottom = Vips::Image.black(8, 8) + 40
    top.join(bottom, :vertical).gifsave_buffer(page_height: 8)
  end

  def uploaded(bytes, type:, name:)
    file = Tempfile.new([ "photo", File.extname(name) ])
    file.binmode
    file.write(bytes)
    file.rewind
    Rack::Test::UploadedFile.new(file.path, type, original_filename: name)
  end

  def upload_photo(owner, bytes = png_bytes, type: "image/png", name: "pixel.png")
    post "/api/v1/profiles/me/photo",
         params: { photo: uploaded(bytes, type: type, name: name) },
         headers: headers_for(owner)
  end

  it "attaches a profile photo only on that profile" do
    user.profile.profile_photo.attach(
      io: StringIO.new(png_bytes),
      filename: "pixel.png",
      content_type: "image/png",
      key: "profile-photos/#{ActiveStorage::Blob.generate_unique_secure_token}"
    )

    attachment = user.profile.profile_photo
    expect(attachment).to be_attached
    expect(attachment.record).to eq(user.profile)
    expect(attachment.name).to eq("profile_photo")
    expect(attachment.blob.key).to start_with("profile-photos/")
  end

  it "stores a square still image and ignores a mismatched declared type" do
    upload_photo(user, type: "image/jpeg", name: "mislabeled.jpg")

    expect(response).to have_http_status(:ok)
    details = response.parsed_body.dig("profile", "details")
    expect(details["image_url"]).to include("/rails/active_storage/")
    expect(details["profile_photo_thumb_url"]).to include("/rails/active_storage/")
    expect(user.profile.reload.image_url).to be_nil
    expect(user.profile.profile_photo.blob.key).to start_with("profile-photos/")
    expect(user.profile.profile_photo.blob.content_type).to eq("image/png")
  end

  it "replaces the previous photo" do
    upload_photo(user)
    first_key = user.profile.reload.profile_photo.blob.key

    upload_photo(user)
    expect(response).to have_http_status(:ok)
    expect(user.profile.reload.profile_photo.blob.key).not_to eq(first_key)
    expect(ActiveStorage::Blob.find_by(key: first_key)).to be_nil
  end

  it "rejects an oversized file, an svg, an animation, and a huge image without clearing the current photo" do
    upload_photo(user)
    kept = user.profile.reload.profile_photo.blob.key

    upload_photo(user, png_bytes + ("x" * 5.megabytes), name: "big.png")
    expect(response).to have_http_status(:unprocessable_entity)
    expect(user.profile.reload.profile_photo.blob.key).to eq(kept)

    upload_photo(user, "<svg xmlns=\"http://www.w3.org/2000/svg\"></svg>", type: "image/png", name: "pixel.svg")
    expect(response).to have_http_status(:unprocessable_entity)
    expect(user.profile.reload.profile_photo.blob.key).to eq(kept)

    upload_photo(user, animated_gif_bytes, type: "image/gif", name: "loop.gif")
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body.dig("error", "message")).to include("still")
    expect(user.profile.reload.profile_photo.blob.key).to eq(kept)

    stub_const("Profiles::AttachPhoto::MAX_PIXELS", 0)
    upload_photo(user)
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body.dig("error", "message")).to include("too large")
    expect(user.profile.reload.profile_photo.blob.key).to eq(kept)
  end

  it "rejects the 11th upload in an hour and keeps the current photo" do
    upload_photo(user)
    kept = user.profile.reload.profile_photo.blob.key
    user.profile.update!(photo_upload_attempts: 10, photo_upload_window_started_at: Time.current)

    upload_photo(user)

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body.dig("error", "code")).to eq("rate_limited")
    expect(user.profile.reload.profile_photo.blob.key).to eq(kept)
  end

  it "returns signed photo urls only to viewers who can see the profile" do
    upload_photo(user)
    other = create_onboarded_adult(email: "photo-viewer@example.com")

    get "/api/v1/profiles/#{user.profile.slug}", headers: headers_for(other)
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig("profile", "details", "image_url")).to be_present

    user.update!(onboarding_path: "organization_invited")
    user.age_visibility_preference.require_visibility_review!

    get "/api/v1/profiles/#{user.profile.slug}", headers: headers_for(other)
    expect(response).to have_http_status(:not_found)
    expect(response.body).not_to include("active_storage")

    get "/api/v1/profiles/me", headers: headers_for(user)
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig("profile", "details", "image_url")).to be_present
  end

  it "ignores an image address on profile update" do
    patch "/api/v1/profiles/me",
          params: { image_url: "https://example.com/secret.jpg", bio: "Still here" },
          headers: headers_for(user),
          as: :json

    expect(response).to have_http_status(:ok)
    expect(user.profile.reload.image_url).to be_nil
    expect(user.profile.bio).to eq("Still here")
    expect(response.parsed_body.dig("profile", "details", "image_url")).to be_nil
    expect(user.profile.profile_photo).not_to be_attached
  end

  it "removes the photo and deletes the blob" do
    upload_photo(user)
    key = user.profile.reload.profile_photo.blob.key

    delete "/api/v1/profiles/me/photo", headers: headers_for(user)

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig("profile", "details", "image_url")).to be_nil
    expect(user.profile.reload.profile_photo).not_to be_attached
    expect(user.profile.slug).to be_present
    expect(ActiveStorage::Blob.find_by(key: key)).to be_nil
  end

  it "rejects a signed-out client and an impersonation write" do
    post "/api/v1/profiles/me/photo", params: { photo: uploaded(png_bytes, type: "image/png", name: "pixel.png") }
    expect(response).to have_http_status(:unauthorized)

    admin = create_onboarded_adult(email: "photo-admin@example.com")
    PlatformStaff.create!(user: admin, role: PlatformStaff::ROLE, active: true)
    post "/api/v1/platform_admin/impersonation",
         params: { user_id: user.id, reason: "support" },
         headers: staff_headers(admin),
         as: :json
    session_id = response.parsed_body["session_id"]

    post "/api/v1/profiles/me/photo",
         params: { photo: uploaded(png_bytes, type: "image/png", name: "pixel.png") },
         headers: staff_headers(admin).merge("X-Impersonation-Session" => session_id)
    expect(response).to have_http_status(:forbidden)
    expect(user.profile.reload.profile_photo).not_to be_attached
  end

  it "purges the photo during account anonymization" do
    upload_photo(user)
    key = user.profile.reload.profile_photo.blob.key
    country = user.profile.country

    PlatformAdmin::AnonymizeDue.anonymize!(user)

    expect(user.profile.reload.profile_photo).not_to be_attached
    expect(ActiveStorage::Blob.find_by(key: key)).to be_nil
    expect(user.profile.display_name).to eq("Deleted user")
    expect(user.profile.country).to eq(country)
  end

  it "does not log a filename when a photo is rejected" do
    lines = []
    allow(Rails.logger).to receive(:info).and_wrap_original do |method, *args, &block|
      lines << args.map(&:to_s).join(" ")
      method.call(*args, &block)
    end

    upload_photo(user, "<svg xmlns=\"http://www.w3.org/2000/svg\"></svg>", type: "image/svg+xml", name: "secret-name.svg")

    expect(response).to have_http_status(:unprocessable_entity)
    rejected = lines.find { |line| line.include?("profile_photo_rejected") }
    expect(rejected).to be_present
    expect(rejected).not_to include("secret-name")
    expect(rejected).not_to include("http")
  end
end
