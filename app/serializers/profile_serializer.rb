# frozen_string_literal: true

class ProfileSerializer
  DETAIL_FIELDS = %i[
    display_name country state_region career_goal
    current_role_term_id current_role_other experience_level
    target_role_term_id target_role_other
    bio image_url github_url linkedin_url portfolio_url interests slug
  ].freeze

  PUBLIC_FIELDS = %i[
    display_name country state_region career_goal
    current_role_term_id current_role_other experience_level
    target_role_term_id target_role_other
    bio image_url github_url linkedin_url portfolio_url interests slug
  ].freeze

  def self.own(user)
    new(user: user, viewer: user, public_view: false).as_json
  end

  def self.public_for(user, viewer:)
    new(user: user, viewer: viewer, public_view: true).as_json
  end

  def initialize(user:, viewer:, public_view:)
    @user = user
    @viewer = viewer
    @public_view = public_view
    @profile = user.profile
  end

  def as_json
    raise DomainError.new("Profile not found", code: "not_found", status: :not_found) if @profile.nil?

    fields = @public_view ? PUBLIC_FIELDS : DETAIL_FIELDS
    details = fields.index_with { |field| @profile.public_send(field) }

    {
      user_id: @user.id,
      visibility: Profiles::Visibility.code_for(@user),
      public_identity_visible: @user.public_identity_visible?,
      age_visibility: {
        visibility_review_required: @user.age_visibility_preference&.visibility_review_required || false,
        public_identity_confirmed: @user.age_visibility_preference&.public_identity_confirmed || false,
        confirmed_at: @user.age_visibility_preference&.confirmed_at
      },
      details: details,
      stats: Profiles::Stats.call(user: @user),
      evidence: Profiles::Evidence.call(user: @user),
      projects: Profiles::ProjectSummaries.call(user: @user, public_view: @public_view),
      links: links_json
    }
  end

  private

  def links_json
    return [] if @public_view && !@user.public_identity_visible?

    [
      { provider: "github", url: @profile.github_url },
      { provider: "linkedin", url: @profile.linkedin_url },
      { provider: "portfolio", url: @profile.portfolio_url }
    ].select { |row| row[:url].present? }
  end
end
