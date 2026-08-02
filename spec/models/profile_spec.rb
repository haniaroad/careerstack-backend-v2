# frozen_string_literal: true

require "rails_helper"

RSpec.describe Profile do
  let(:user) { create_user(email: "profile@example.com") }

  it "requires the minimum profile fields" do
    profile = Profile.new(user: user)

    expect(profile).not_to be_valid
    expect(profile.errors.attribute_names).to include(:display_name, :country, :state_region, :career_goal)
  end

  it "restricts experience level to the allowed values" do
    profile = Profile.new(minimum_profile_attributes(user: user, experience_level: "expert"))

    expect(profile).not_to be_valid
    expect(profile.errors[:experience_level]).to be_present
  end

  it "accepts at most ten interest tags" do
    profile = Profile.new(minimum_profile_attributes(user: user, interests: (1..11).map { |n| "tag-#{n}" }))

    expect(profile).not_to be_valid
    expect(profile.errors[:interests].join).to match(/at most 10/)
  end

  describe "date of birth protection" do
    subject(:profile) { user.create_profile!(minimum_profile_attributes(date_of_birth: Date.new(2011, 6, 15))) }

    it "keeps the column out of serializable_hash" do
      expect(profile.serializable_hash).not_to have_key("date_of_birth")
    end

    it "keeps the value out of to_json" do
      expect(profile.to_json).not_to include("2011-06-15")
    end

    it "keeps the column out even when a caller asks for other exclusions" do
      expect(profile.serializable_hash(except: [ :bio ])).not_to have_key("date_of_birth")
    end

    it "still stores the value for server-side age derivation" do
      expect(profile.reload.date_of_birth).to eq(Date.new(2011, 6, 15))
    end
  end

  it "masks date_of_birth in request logs" do
    filter = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)

    expect(filter.filter("date_of_birth" => "2011-06-15")).to eq("date_of_birth" => "[FILTERED]")
  end
end
