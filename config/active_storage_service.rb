# frozen_string_literal: true

module CareerStack
  # Cloud Run must not fall back to Disk. Instance disk is ephemeral, not
  # shared across instances, and files written there cannot be recovered.
  # Local Docker has no K_SERVICE and keeps Disk.
  module ActiveStorageService
    module_function

    def select(gcs_bucket:, cloud_run:)
      return :google if gcs_bucket && !gcs_bucket.empty?

      if cloud_run && !cloud_run.empty?
        raise "GCS_BUCKET is required on Cloud Run. Evidence files must not use instance disk storage. Files already stored only on an instance disk cannot be recovered."
      end

      :local
    end
  end
end
