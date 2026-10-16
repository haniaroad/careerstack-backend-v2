# frozen_string_literal: true

module Profiles
  class AttachPhoto
    MAX_BYTES = 5.megabytes
    MAX_PIXELS = 24_000_000
    HOURLY_LIMIT = 10
    ALLOWED_TYPES = {
      "image/jpeg" => "jpg",
      "image/png" => "png",
      "image/webp" => "webp",
      "image/gif" => "gif"
    }.freeze

    def self.call(user:, upload:)
      new(user: user, upload: upload).call
    end

    def initialize(user:, upload:)
      @user = user
      @upload = upload
    end

    def call
      profile = @user.profile
      raise DomainError.new("Profile not found", code: "not_found", status: :not_found) if profile.nil?

      consume_attempt!(profile)
      data = read_upload
      detected = detect_type(data)
      inspect_image!(data, detected)
      replace_photo!(profile, data, detected)
      profile
    end

    private

    def consume_attempt!(profile)
      profile.with_lock do
        now = Time.current
        started = profile.photo_upload_window_started_at
        attempts = if started.nil? || started <= 1.hour.ago
          profile.photo_upload_window_started_at = now
          1
        else
          profile.photo_upload_attempts + 1
        end

        if attempts > HOURLY_LIMIT
          reject!("rate_limited", "You can upload 10 photos per hour. Try again later.")
        end

        profile.photo_upload_attempts = attempts
        profile.save!
      end
    end

    def read_upload
      unless @upload.respond_to?(:read)
        reject!("validation_error", "Choose a photo to upload.")
      end

      @upload.rewind if @upload.respond_to?(:rewind)
      data = @upload.read
      @upload.rewind if @upload.respond_to?(:rewind)
      if data.blank? || data.bytesize > MAX_BYTES
        reject!("validation_error", "Photo must be 5 MB or smaller.")
      end
      data
    end

    def detect_type(data)
      require "marcel"
      type = Marcel::MimeType.for(StringIO.new(data))
      return type if ALLOWED_TYPES.key?(type)

      reject!(
        "validation_error",
        "Use a JPEG, PNG, WebP, or still GIF.",
        detected_type: type
      )
    end

    def inspect_image!(data, detected)
      require "vips"
      image = Vips::Image.new_from_buffer(data, "")
      frames = image.get_typeof("n-pages") != 0 ? image.get("n-pages").to_i : 1
      if frames > 1
        reject!("validation_error", "Use a still image, not an animation.", detected_type: detected)
      end
      if image.width * image.height > MAX_PIXELS
        reject!("validation_error", "That image is too large to process.", detected_type: detected)
      end
    rescue DomainError
      raise
    rescue StandardError
      reject!("validation_error", "That photo could not be saved.", detected_type: detected)
    end

    def replace_photo!(profile, data, detected)
      blob = ActiveStorage::Blob.create_and_upload!(
        io: StringIO.new(data),
        filename: "profile.#{ALLOWED_TYPES.fetch(detected)}",
        content_type: detected,
        key: "profile-photos/#{ActiveStorage::Blob.generate_unique_secure_token}",
        identify: false
      )
      blob.variant(PhotoUrls::DISPLAY).processed
      blob.variant(PhotoUrls::THUMB).processed
      profile.profile_photo.purge if profile.profile_photo.attached?
      profile.profile_photo.attach(blob)
      profile.update!(image_url: nil)
    rescue DomainError
      raise
    rescue StandardError
      blob&.purge
      reject!("validation_error", "That photo could not be saved.", detected_type: detected)
    end

    def reject!(code, message, detected_type: nil)
      Rails.logger.info(
        {
          event: "profile_photo_rejected",
          code: code,
          detected_type: detected_type
        }.to_json
      )
      raise DomainError.new(message, code: code)
    end
  end
end
