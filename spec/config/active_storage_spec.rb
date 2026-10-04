# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Active Storage services" do
  it "keeps deployed google storage on private GCS and local disk separate" do
    config = YAML.safe_load(ERB.new(Rails.root.join("config/storage.yml").read).result, aliases: true)

    expect(config.dig("local", "service")).to eq("Disk")
    expect(config.dig("test", "service")).to eq("Disk")
    expect(config.dig("google", "service")).to eq("GCS")
    expect(config.dig("google", "public")).to eq(false)
    expect(config.dig("google", "iam")).to eq(true)
  end
end
