# frozen_string_literal: true

module Profiles
  # Builds a stable lowercase kebab-case slug from a display name, appending a
  # short random suffix when the base collides with an existing slug.
  class SlugGenerator
    SUFFIX_LENGTH = 4
    MAX_ATTEMPTS = 12

    def self.call(display_name:, exclude_profile_id: nil)
      new(display_name: display_name, exclude_profile_id: exclude_profile_id).call
    end

    def initialize(display_name:, exclude_profile_id: nil)
      @display_name = display_name.to_s
      @exclude_profile_id = exclude_profile_id
    end

    def call
      base = parameterize(@display_name)
      base = "member" if base.blank?

      candidate = base
      return candidate unless taken?(candidate)

      MAX_ATTEMPTS.times do
        candidate = "#{base}-#{SecureRandom.alphanumeric(SUFFIX_LENGTH).downcase}"
        return candidate unless taken?(candidate)
      end

      "#{base}-#{SecureRandom.uuid.split('-').first}"
    end

    private

    def parameterize(value)
      value.unicode_normalize(:nfkd)
           .gsub(/[^\x00-\x7F]/, "")
           .downcase
           .gsub(/[^a-z0-9]+/, "-")
           .gsub(/\A-+|-+\z/, "")
           .slice(0, 48)
           .to_s
           .gsub(/-+\z/, "")
    end

    def taken?(slug)
      scope = Profile.where(slug: slug)
      scope = scope.where.not(id: @exclude_profile_id) if @exclude_profile_id.present?
      scope.exists?
    end
  end
end
