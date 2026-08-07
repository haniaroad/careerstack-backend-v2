# frozen_string_literal: true

class AiGeneration < ApplicationRecord
  USE_CASE_PROJECT_DRAFT = "project_draft_generation"
  USE_CASES = [ USE_CASE_PROJECT_DRAFT ].freeze

  STATUS_PENDING = "pending"
  STATUS_RUNNING = "running"
  STATUS_SUCCEEDED = "succeeded"
  STATUS_FAILED = "failed"
  STATUSES = [ STATUS_PENDING, STATUS_RUNNING, STATUS_SUCCEEDED, STATUS_FAILED ].freeze

  belongs_to :user
  belongs_to :workspace
  belongs_to :project, optional: true

  validates :use_case, inclusion: { in: USE_CASES }
  validates :status, inclusion: { in: STATUSES }
  validates :prompt, presence: true
  validates :prompt_digest, presence: true

  scope :succeeded, -> { where(status: STATUS_SUCCEEDED) }
  scope :for_user, ->(user) { where(user_id: user.id) }

  def pending?
    status == STATUS_PENDING
  end

  def running?
    status == STATUS_RUNNING
  end

  def succeeded?
    status == STATUS_SUCCEEDED
  end

  def failed?
    status == STATUS_FAILED
  end

  def owner?(user)
    user_id == user.id
  end
end
