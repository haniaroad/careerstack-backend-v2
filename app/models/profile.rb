# frozen_string_literal: true

class Profile < ApplicationRecord
  EXPERIENCE_LEVELS = %w[beginner intermediate advanced].freeze
  MAX_INTERESTS = 10

  belongs_to :user
  belongs_to :current_role_term, class_name: "TaxonomyTerm", optional: true
  belongs_to :target_role_term, class_name: "TaxonomyTerm", optional: true

  validates :display_name, :country, :state_region, :career_goal, presence: true
  validates :experience_level, inclusion: { in: EXPERIENCE_LEVELS }
  validate :interests_within_limit

  # Defense in depth against date of birth leaking through an incidental
  # `render json: profile` or `to_json`. Serializers enumerate fields explicitly;
  # this guarantees the column stays out even if one forgets.
  def serializable_hash(options = nil)
    options ||= {}
    excluded = Array(options[:except]).map(&:to_s) | %w[date_of_birth]
    super(options.merge(except: excluded))
  end

  private

  def interests_within_limit
    return if interests.blank?

    unless interests.is_a?(Array)
      errors.add(:interests, "must be a list of tags")
      return
    end

    errors.add(:interests, "may include at most #{MAX_INTERESTS} tags") if interests.size > MAX_INTERESTS
  end
end
