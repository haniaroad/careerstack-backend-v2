# frozen_string_literal: true

class Taxonomy < ApplicationRecord
  has_many :taxonomy_terms, dependent: :destroy

  validates :key, :name, presence: true
  validates :key, uniqueness: true
end
