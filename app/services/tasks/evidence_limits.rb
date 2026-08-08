# frozen_string_literal: true

module Tasks
  module EvidenceLimits
    MAX_FILES = 3
    MAX_FILE_BYTES = 10.megabytes
    MAX_COMBINED_BYTES = 25.megabytes

    ALLOWED_CONTENT_TYPES = %w[
      text/plain
      application/pdf
      application/vnd.openxmlformats-officedocument.wordprocessingml.document
      image/png
      image/jpeg
      application/vnd.openxmlformats-officedocument.spreadsheetml.sheet
      text/csv
      application/csv
      audio/mpeg
      audio/wav
      video/mp4
      video/quicktime
      application/octet-stream
    ].freeze

    ANALYZABLE_CONTENT_TYPES = %w[
      text/plain
      application/pdf
      application/vnd.openxmlformats-officedocument.wordprocessingml.document
      image/png
      image/jpeg
    ].freeze

    module_function

    def validate_files!(blobs)
      raise DomainError.new("At most three files per submission", code: "validation_error") if blobs.size > MAX_FILES

      combined = 0
      blobs.each do |blob|
        raise DomainError.new("File exceeds 10 MB limit", code: "validation_error") if blob.byte_size > MAX_FILE_BYTES

        combined += blob.byte_size
        unless ALLOWED_CONTENT_TYPES.include?(blob.content_type.to_s)
          raise DomainError.new("Unsupported file type: #{blob.content_type}", code: "validation_error")
        end
      end

      raise DomainError.new("Combined file size exceeds 25 MB", code: "validation_error") if combined > MAX_COMBINED_BYTES
    end

    def analyzable?(content_type)
      ANALYZABLE_CONTENT_TYPES.include?(content_type.to_s)
    end
  end
end
