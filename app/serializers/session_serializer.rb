# frozen_string_literal: true

# The single payload the client needs to render the shell: identity, profile,
# workspace grants, active workspace, org-admin access, and visibility flags.
#
# Date of birth is deliberately absent. Fields are enumerated explicitly rather
# than dumped from the model so a future column cannot leak by default.
class SessionSerializer
  PROFILE_FIELDS = %i[
    display_name country state_region career_goal
    current_role_term_id current_role_other experience_level
    target_role_term_id target_role_other
    bio image_url github_url linkedin_url portfolio_url interests slug
  ].freeze

  def self.call(user)
    new(user).as_json
  end

  def initialize(user)
    @user = user
  end

  def as_json
    active_workspace = @user.resolved_active_workspace

    {
      user: user_json,
      profile: profile_json,
      workspaces: @user.usable_workspaces.map { |workspace| WorkspaceSerializer.call(workspace) },
      active_workspace_id: active_workspace&.id,
      active_workspace: WorkspaceSerializer.call(active_workspace),
      can_access_org_admin: @user.can_access_org_admin_for?(active_workspace),
      org_admin_capabilities: org_admin_capabilities(active_workspace),
      age_visibility: age_visibility_json,
      program_filter: program_filter_json(active_workspace),
      credits: credits_json(active_workspace)
    }
  end

  private

  def credits_json(workspace)
    return nil if workspace.nil?

    owner = workspace.organization_id.present? ? workspace.organization : @user
    Credits::Balance.summary(owner: owner)
  end

  def user_json
    {
      id: @user.id,
      email: @user.email,
      status: @user.status,
      age_status: @user.age_status,
      onboarding_path: @user.onboarding_path,
      onboarding_complete: !@user.pending_onboarding?,
      terms_accepted_at: @user.terms_accepted_at,
      personal_trial_granted: @user.personal_trial_granted,
      organization_trial_granted: @user.organization_trial_granted,
      public_identity_visible: @user.public_identity_visible?
    }
  end

  def profile_json
    profile = @user.profile
    return nil if profile.nil?

    Profiles::AssignSlug.call(profile: profile) if profile.slug.blank?
    profile.reload
    PROFILE_FIELDS.index_with { |field| profile.public_send(field) }.merge(
      visibility: Profiles::Visibility.code_for(@user)
    )
  end

  def age_visibility_json
    preference = @user.age_visibility_preference

    {
      visibility_review_required: preference&.visibility_review_required || false,
      public_identity_confirmed: preference&.public_identity_confirmed || false,
      confirmed_at: preference&.confirmed_at
    }
  end

  # Programs are context inside an organization workspace, not workspaces of
  # their own, and the filter defaults to all programs (D-9).
  def program_filter_json(workspace)
    return nil if workspace&.organization_id.blank?

    membership = @user.membership_for(workspace.organization)
    program_id = membership&.program_filter_program_id

    {
      mode: program_id.present? ? "program" : "all",
      program_id: program_id,
      available_programs: available_programs(workspace.organization).map { |p| { id: p.id, name: p.name, status: p.status } }
    }
  end

  def available_programs(organization)
    membership = @user.membership_for(organization)
    scope = organization.programs.order(:name)
    return scope if membership&.staff?

    scope.active
  end

  def org_admin_capabilities(workspace)
    membership = workspace&.organization && @user.membership_for(workspace.organization)
    return nil unless membership&.staff?

    {
      can_archive_programs: membership.can_archive_programs?,
      can_delete_empty_drafts: membership.can_delete_empty_drafts?,
      can_remove_members: membership.can_remove_members?,
      can_view_credit_history: membership.can_view_credit_history?,
      can_submit_upgrade_request: membership.administrator?
    }
  end
end
