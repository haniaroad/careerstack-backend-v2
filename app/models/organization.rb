# frozen_string_literal: true

class Organization < ApplicationRecord
  belongs_to :structure_term, class_name: "TaxonomyTerm", optional: true
  belongs_to :primary_goal_term, class_name: "TaxonomyTerm", optional: true
  has_one :workspace, dependent: :destroy
  has_many :programs, dependent: :destroy
  has_many :organization_memberships, dependent: :destroy
  has_many :users, through: :organization_memberships
  has_many :invitations, dependent: :destroy
  has_many :credit_ledger_entries, as: :owner, dependent: :restrict_with_exception

  validates :name, :country, :state_region, :timezone, presence: true
end
