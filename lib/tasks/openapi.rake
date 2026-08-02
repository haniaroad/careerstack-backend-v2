# frozen_string_literal: true

namespace :openapi do
  desc "Validate the OpenAPI document can be loaded as YAML with required paths"
  task validate: :environment do
    require "yaml"

    path = Rails.root.join("openapi/openapi.yaml")
    raise "Missing OpenAPI document at #{path}" unless path.exist?

    doc = YAML.safe_load(path.read, permitted_classes: [ Date, Time ], aliases: true)
    raise "OpenAPI document must be a Hash" unless doc.is_a?(Hash)
    raise "OpenAPI version missing" unless doc["openapi"].to_s.start_with?("3.")

    paths = doc.fetch("paths")
    %w[/health /ready].each do |required_path|
      raise "Missing path #{required_path}" unless paths.key?(required_path)
    end

    schemas = doc.dig("components", "schemas") || {}
    raise "Missing ErrorEnvelope schema" unless schemas.key?("ErrorEnvelope")

    puts "OpenAPI document is valid (#{path})"
  end
end
