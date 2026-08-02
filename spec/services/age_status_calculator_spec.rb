# frozen_string_literal: true

require "rails_helper"

RSpec.describe AgeStatusCalculator do
  def status_for(date_of_birth, timezone: "UTC", as_of: Time.current)
    described_class.call(date_of_birth: date_of_birth, timezone: timezone, as_of: as_of)
  end

  it "returns unknown only when the date of birth is missing" do
    expect(status_for(nil)).to eq("unknown")
  end

  it "returns adult from the start of the 18th birthday" do
    as_of = Time.utc(2026, 8, 2, 0, 5)

    expect(status_for(Date.new(2008, 8, 2), as_of: as_of)).to eq("adult")
  end

  it "returns minor on the day before the 18th birthday" do
    as_of = Time.utc(2026, 8, 2, 23, 59)

    expect(status_for(Date.new(2008, 8, 3), as_of: as_of)).to eq("minor")
  end

  it "returns minor for someone under the minimum registration age" do
    expect(status_for(Date.new(2020, 1, 1), as_of: Time.utc(2026, 8, 2))).to eq("minor")
  end

  describe "organization timezone boundary" do
    # 02:00 UTC on the birthday is still the previous day in Los Angeles.
    let(:as_of) { Time.utc(2026, 8, 2, 2, 0) }
    let(:date_of_birth) { Date.new(2008, 8, 2) }

    it "treats the user as adult where the birthday has started" do
      expect(status_for(date_of_birth, timezone: "UTC", as_of: as_of)).to eq("adult")
    end

    it "treats the user as a minor where the birthday has not started yet" do
      expect(status_for(date_of_birth, timezone: "America/Los_Angeles", as_of: as_of)).to eq("minor")
    end

    it "falls back to UTC for a blank timezone" do
      expect(status_for(date_of_birth, timezone: nil, as_of: as_of)).to eq("adult")
    end
  end

  describe ".age_in_years" do
    it "returns nil without a date of birth" do
      expect(described_class.age_in_years(date_of_birth: nil)).to be_nil
    end

    it "does not count a birthday that has not happened yet this year" do
      age = described_class.age_in_years(date_of_birth: Date.new(2000, 12, 31), as_of: Time.utc(2026, 8, 2))

      expect(age).to eq(25)
    end

    it "counts the birthday on the day it occurs" do
      age = described_class.age_in_years(date_of_birth: Date.new(2000, 8, 2), as_of: Time.utc(2026, 8, 2))

      expect(age).to eq(26)
    end
  end

  describe ".below_minimum_registration_age?" do
    it "is true under 13" do
      expect(
        described_class.below_minimum_registration_age?(date_of_birth: Date.new(2015, 1, 1), as_of: Time.utc(2026, 8, 2))
      ).to be(true)
    end

    it "is false on the 13th birthday" do
      expect(
        described_class.below_minimum_registration_age?(date_of_birth: Date.new(2013, 8, 2), as_of: Time.utc(2026, 8, 2))
      ).to be(false)
    end

    it "is false without a date of birth" do
      expect(described_class.below_minimum_registration_age?(date_of_birth: nil)).to be(false)
    end
  end
end
