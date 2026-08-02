# frozen_string_literal: true

class Program < ApplicationRecord
  belongs_to :organization
  has_many :invitations, dependent: :nullify

  validates :name, presence: true
end
