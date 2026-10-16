# frozen_string_literal: true

require "rails_helper"

RSpec.describe Profiles::ClearLegacyImageUrls do
  include IdentityFixtures

  it "nulls image_url and leaves the other profile columns unchanged" do
    user = create_onboarded_adult(email: "legacy-photo@example.com")
    profile = user.profile
    profile.update_columns(
      image_url: "https://example.com/old.jpg",
      bio: "Keep this bio",
      display_name: "Keep This Name"
    )

    described_class.call

    profile.reload
    expect(profile.image_url).to be_nil
    expect(profile.bio).to eq("Keep this bio")
    expect(profile.display_name).to eq("Keep This Name")
    expect(profile.slug).to be_present
  end
end
