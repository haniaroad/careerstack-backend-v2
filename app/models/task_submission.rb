# frozen_string_literal: true

class TaskSubmission < ApplicationRecord
  belongs_to :task
  belongs_to :submitted_by, class_name: "User"
  has_many :links, class_name: "TaskSubmissionLink", dependent: :destroy
  has_many :ai_reviews, dependent: :destroy
  has_many_attached :files

  validates :attempt_number, numericality: { only_integer: true, greater_than: 0 }
  validates :content_fingerprint, presence: true
  validates :submitted_at, presence: true
  validate :has_evidence

  private

  def has_evidence
    return if body.present?
    return if links.any?
    return if files.attached?

    errors.add(:base, "Submission requires text and/or evidence")
  end
end
