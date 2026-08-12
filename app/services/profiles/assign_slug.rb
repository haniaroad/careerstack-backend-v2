# frozen_string_literal: true

module Profiles
  # Assigns a slug once. Never regenerates when the display name changes.
  class AssignSlug
    def self.call(profile:)
      new(profile: profile).call
    end

    def initialize(profile:)
      @profile = profile
    end

    def call
      return @profile if @profile.slug.present?

      slug = SlugGenerator.call(display_name: @profile.display_name, exclude_profile_id: @profile.id)
      @profile.update!(slug: slug)
      @profile
    end
  end
end
