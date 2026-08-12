# frozen_string_literal: true

class Profile < ApplicationRecord
  EXPERIENCE_LEVELS = %w[beginner intermediate advanced].freeze
  MAX_INTERESTS = 10

  belongs_to :user
  belongs_to :current_role_term, class_name: "TaxonomyTerm", optional: true
  belongs_to :target_role_term, class_name: "TaxonomyTerm", optional: true

  validates :display_name, :country, :state_region, :career_goal, presence: true
  validates :experience_level, inclusion: { in: EXPERIENCE_LEVELS }
  validates :slug, presence: true, uniqueness: true
  validate :interests_within_limit
  validate :slug_immutable, on: :update

  before_validation :assign_slug_if_blank, on: :create

  # Defense in depth against date of birth leaking through an incidental
  # `render json: profile` or `to_json`. Serializers enumerate fields explicitly;
  # this guarantees the column stays out even if one forgets.
  def serializable_hash(options = nil)
    options ||= {}
    excluded = Array(options[:except]).map(&:to_s) | %w[date_of_birth]
    super(options.merge(except: excluded))
  end

  private

  def assign_slug_if_blank
    return if slug.present?

    self.slug = Profiles::SlugGenerator.call(display_name: display_name, exclude_profile_id: id)
  end

  def interests_within_limit
    return if interests.blank?

    unless interests.is_a?(Array)
      errors.add(:interests, "must be a list of tags")
      return
    end

    errors.add(:interests, "may include at most #{MAX_INTERESTS} tags") if interests.size > MAX_INTERESTS
  end

  def slug_immutable
    return unless slug_changed? && slug_was.present?

    errors.add(:slug, "cannot be changed")
  end
end
