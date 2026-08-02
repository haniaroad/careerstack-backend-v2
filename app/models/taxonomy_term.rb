# frozen_string_literal: true

class TaxonomyTerm < ApplicationRecord
  belongs_to :taxonomy

  validates :key, :label, presence: true
  validates :key, uniqueness: { scope: :taxonomy_id }
end
