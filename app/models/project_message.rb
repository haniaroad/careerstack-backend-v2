# frozen_string_literal: true

class ProjectMessage < ApplicationRecord
  MAX_BODY_LENGTH = 2000

  belongs_to :project
  belongs_to :author, class_name: "User"
  has_many :reports, class_name: "ProjectMessageReport", dependent: :destroy

  validates :body, presence: true, length: { maximum: MAX_BODY_LENGTH }
end
