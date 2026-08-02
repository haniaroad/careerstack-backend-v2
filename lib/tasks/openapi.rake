# frozen_string_literal: true

namespace :openapi do
  desc "Validate the OpenAPI document loads, declares required paths, and resolves every internal $ref"
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

    dangling = OpenapiRefChecker.dangling_refs(doc)
    raise "Unresolved $ref(s): #{dangling.join(', ')}" if dangling.any?

    puts "OpenAPI document is valid (#{path}): #{paths.size} paths, #{schemas.size} schemas"
  end
end

# Walks the document and reports local "#/..." references that do not resolve.
module OpenapiRefChecker
  def self.dangling_refs(doc)
    collect_refs(doc).uniq.reject { |ref| resolvable?(doc, ref) }
  end

  def self.collect_refs(node)
    case node
    when Hash
      refs = node["$ref"].is_a?(String) ? [ node["$ref"] ] : []
      refs + node.flat_map { |key, value| key == "$ref" ? [] : collect_refs(value) }
    when Array
      node.flat_map { |value| collect_refs(value) }
    else
      []
    end
  end

  def self.resolvable?(doc, ref)
    # External references are out of scope for this check.
    return true unless ref.start_with?("#/")

    segments = ref.delete_prefix("#/").split("/").map { |segment| segment.gsub("~1", "/").gsub("~0", "~") }
    !doc.dig(*segments).nil?
  end
end
