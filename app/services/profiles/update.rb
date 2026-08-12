# frozen_string_literal: true

module Profiles
  class Update
    ALLOWED = %i[
      display_name country state_region career_goal
      current_role_term_id current_role_other experience_level
      target_role_term_id target_role_other
      bio image_url github_url linkedin_url portfolio_url interests
    ].freeze

    def self.call(user:, params:)
      new(user: user, params: params).call
    end

    def initialize(user:, params:)
      @user = user
      @params = params.to_h.with_indifferent_access.slice(*ALLOWED.map(&:to_s))
    end

    def call
      profile = @user.profile
      raise DomainError.new("Profile not found", code: "not_found", status: :not_found) if profile.nil?

      if @params.key?(:interests)
        interests = Array(@params[:interests]).map { |tag| tag.to_s.strip }.reject(&:blank?).uniq
        raise DomainError.new("interests may include at most #{Profile::MAX_INTERESTS} tags", code: "validation_error") if interests.size > Profile::MAX_INTERESTS

        @params[:interests] = interests
      end

      if @params.key?(:experience_level) && Profile::EXPERIENCE_LEVELS.exclude?(@params[:experience_level].to_s)
        raise DomainError.new("experience_level must be beginner, intermediate, or advanced", code: "validation_error")
      end

      %w[github_url linkedin_url portfolio_url image_url].each do |field|
        next unless @params.key?(field)

        value = @params[field].to_s.strip
        @params[field] = value.presence
        next if @params[field].blank?
        next if @params[field].match?(/\Ahttps:\/\//i)

        raise DomainError.new("#{field} must be an https URL", code: "validation_error")
      end

      profile.assign_attributes(@params)
      unless profile.save
        raise DomainError.new(profile.errors.full_messages.to_sentence, code: "validation_error")
      end

      # Slug is never regenerated on display-name change.
      Profiles::AssignSlug.call(profile: profile) if profile.slug.blank?
      profile.reload
    end
  end
end
