# frozen_string_literal: true

module Profiles
  class PhotoUrls
    TTL = 15.minutes
    DISPLAY = { resize_to_fill: [ 512, 512 ], format: :webp, saver: { strip: true } }.freeze
    THUMB = { resize_to_fill: [ 96, 96 ], format: :webp, saver: { strip: true } }.freeze

    def self.for(profile)
      new(profile).as_json
    end

    def initialize(profile)
      @profile = profile
    end

    def as_json
      attachment = @profile&.profile_photo
      return empty unless attachment&.attached?

      blob = attachment.blob
      {
        image_url: representation_url(blob, DISPLAY),
        profile_photo_thumb_url: representation_url(blob, THUMB)
      }
    end

    private

    def empty
      { image_url: nil, profile_photo_thumb_url: nil }
    end

    def representation_url(blob, transformations)
      processed = blob.variant(transformations).processed
      options = ActiveStorage::Current.url_options
      options = { host: "www.example.com" } if options.blank? || options[:host].blank?
      Rails.application.routes.url_helpers.rails_representation_url(
        processed,
        disposition: :inline,
        expires_in: TTL,
        **options
      )
    end
  end
end
