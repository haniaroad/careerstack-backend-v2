# frozen_string_literal: true

module Onboarding
  # Normalizes the profile payload shared by both onboarding paths and enforces
  # the minimum-profile rule: name, location, career goal, current role,
  # experience level, and target role. Everything else is skippable.
  class ProfileInput
    MAX_INTERESTS = 10

    REQUIRED_TEXT_FIELDS = %i[display_name country state_region career_goal].freeze

    TEXT_FIELDS = %i[
      display_name country state_region career_goal experience_level
    ].freeze

    OPTIONAL_FIELDS = %i[
      current_role_term_id current_role_other target_role_term_id target_role_other
      bio image_url github_url linkedin_url portfolio_url
    ].freeze

    def initialize(params)
      @params = params
    end

    def attributes
      @attributes ||= begin
        attrs = TEXT_FIELDS.index_with { |field| @params[field].to_s.strip }
        OPTIONAL_FIELDS.each { |field| attrs[field] = @params[field].presence }
        attrs[:interests] = interests
        attrs
      end
    end

    def validate!
      REQUIRED_TEXT_FIELDS.each do |field|
        raise Error, "#{field} is required" if attributes[field].blank?
      end

      unless Profile::EXPERIENCE_LEVELS.include?(attributes[:experience_level])
        raise Error, "experience_level must be one of #{Profile::EXPERIENCE_LEVELS.join(', ')}"
      end

      validate_role!(:current_role, "current role")
      validate_role!(:target_role, "target role")

      validate_term!(:current_role_term_id)
      validate_term!(:target_role_term_id)

      self
    end

    private

    def interests
      Array(@params[:interests]).map { |tag| tag.to_s.strip }.reject(&:blank?).uniq.first(MAX_INTERESTS)
    end

    # A role is satisfied either by a taxonomy term or by free text when the
    # user picked Other.
    def validate_role!(prefix, label)
      return if attributes[:"#{prefix}_term_id"].present?
      return if attributes[:"#{prefix}_other"].present?

      raise Error, "#{label} is required"
    end

    def validate_term!(field)
      term_id = attributes[field]
      return if term_id.blank?
      return if role_term_ids.include?(term_id)

      raise Error, "#{field} is not a known role"
    end

    def role_term_ids
      @role_term_ids ||= TaxonomyTerm.joins(:taxonomy).where(taxonomies: { key: "roles" }).pluck(:id)
    end
  end
end
