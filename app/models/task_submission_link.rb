# frozen_string_literal: true

class TaskSubmissionLink < ApplicationRecord
  belongs_to :task_submission

  validates :url, presence: true, length: { maximum: 2048 }
end
