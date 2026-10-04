# frozen_string_literal: true

require "uri"

module Tasks
  # Briefing-only YouTube URL. www and m hosts are the same allowlist as youtube.com.
  class ReferenceVideo
    def self.normalize!(value)
      return nil if value.nil? || value.to_s.strip.empty?

      raw = value.to_s.strip
      uri = URI.parse(raw)
      host = uri.host&.downcase&.delete_prefix("www.")
      allowed = uri.is_a?(URI::HTTPS) && (
        (host == "youtu.be" && short_id?(uri.path)) ||
        (youtube_host?(host) && watch?(uri)) ||
        (youtube_host?(host) && shorts?(uri.path))
      )
      raise invalid unless allowed

      raw
    rescue URI::InvalidURIError
      raise invalid
    end

    def self.youtube_host?(host)
      host == "youtube.com" || host == "m.youtube.com"
    end

    def self.short_id?(path)
      path.to_s.split("/").reject(&:blank?).length == 1
    end

    def self.watch?(uri)
      return false unless uri.path == "/watch"

      URI.decode_www_form(uri.query.to_s).any? { |key, val| key == "v" && val.present? }
    end

    def self.shorts?(path)
      path.to_s.match?(%r{\A/shorts/[^/]+\z})
    end

    def self.invalid
      DomainError.new(
        "Reference video must be an https YouTube watch, youtu.be, or shorts URL",
        code: "validation_error"
      )
    end

    private_class_method :youtube_host?, :short_id?, :watch?, :shorts?, :invalid
  end
end
