# frozen_string_literal: true

class Workspace < ApplicationRecord
  KINDS = %w[personal organization].freeze

  belongs_to :owner_user, class_name: "User", optional: true
  belongs_to :organization, optional: true

  validates :kind, inclusion: { in: KINDS }
  validates :name, presence: true
  validate :kind_associations

  def personal?
    kind == "personal"
  end

  def organization?
    kind == "organization"
  end

  private

  def kind_associations
    if personal?
      errors.add(:owner_user, "must be present for personal workspaces") if owner_user_id.blank?
      errors.add(:organization, "must be blank for personal workspaces") if organization_id.present?
    elsif organization?
      errors.add(:organization, "must be present for organization workspaces") if organization_id.blank?
      errors.add(:owner_user, "must be blank for organization workspaces") if owner_user_id.present?
    end
  end
end
