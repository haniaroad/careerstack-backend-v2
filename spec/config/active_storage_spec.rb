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

  it "uses GCS on Cloud Run only when a bucket is configured" do
    require Rails.root.join("config/active_storage_service")

    expect(CareerStack::ActiveStorageService.select(gcs_bucket: "evidence", cloud_run: "careerstack-api")).to eq(:google)
    expect(CareerStack::ActiveStorageService.select(gcs_bucket: nil, cloud_run: nil)).to eq(:local)
    expect {
      CareerStack::ActiveStorageService.select(gcs_bucket: nil, cloud_run: "careerstack-api")
    }.to raise_error(/GCS_BUCKET is required/)
  end
end
