# frozen_string_literal: true

class AiExtractionCache < ApplicationRecord
  STATUS_SUCCEEDED = "succeeded"
  STATUS_FAILED = "failed"
  STATUSES = [ STATUS_SUCCEEDED, STATUS_FAILED ].freeze

  validates :blob_digest, presence: true, uniqueness: true
  validates :status, inclusion: { in: STATUSES }
end
