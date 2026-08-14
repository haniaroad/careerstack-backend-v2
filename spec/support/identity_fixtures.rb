# frozen_string_literal: true

# Inline record builders. The project intentionally has no FactoryBot, so these
# are plain helpers over the real models with sensible identity defaults.
module IdentityFixtures
  def term(taxonomy_key, term_key)
    TaxonomyTerm.joins(:taxonomy).find_by!(taxonomies: { key: taxonomy_key }, key: term_key)
  end

  def role_term(term_key = "software_engineer")
    term("roles", term_key)
  end

  def structure_term(term_key = "nonprofit")
    term("organization_structures", term_key)
  end

  def goal_term(term_key = "career_readiness")
    term("organization_goals", term_key)
  end

  def create_user(email:, firebase_uid: nil, **attributes)
    User.create!(
      firebase_uid: firebase_uid || "uid-#{SecureRandom.hex(4)}",
      email: email,
      status: attributes.delete(:status) || User::PENDING_ONBOARDING,
      **attributes
    )
  end

  # A fully onboarded independent adult with Personal workspace and trial credit.
  def create_onboarded_adult(email:, firebase_uid: nil)
    user = create_user(email: email, firebase_uid: firebase_uid)
    user.create_profile!(minimum_profile_attributes)
    preference = user.create_age_visibility_preference!
    preference.confirm_public_identity!
    user.update!(
      status: User::ACTIVE,
      onboarding_path: "independent",
      age_status: AgeStatusCalculator::ADULT,
      age_attested_at: Time.current,
      terms_accepted_at: Time.current
    )
    Workspaces::EnsurePersonal.call(user: user)
    Credits::GrantPersonalTrial.call(user: user)
    user.reload
  end

  def create_organization(name: "STEM Forward", timezone: "UTC", **attributes)
    organization = Organization.create!(
      name: name,
      country: "United States",
      state_region: "MA",
      structure_term: structure_term,
      primary_goal_term: goal_term,
      timezone: timezone,
      **attributes
    )
    Workspaces::EnsureOrganization.call(organization: organization)
    organization.reload
  end

  def create_membership(organization:, user:, role: OrganizationMembership::PARTICIPANT, program: nil)
    membership = OrganizationMembership.create!(organization: organization, user: user, role: role, program: program)
    if program
      membership.program_enrollments.find_or_create_by!(program: program)
    end
    membership
  end

  def create_program(organization:, name: "Spring Cohort", status: Program::STATUS_ACTIVE, **attributes)
    Program.create!(organization: organization, name: name, status: status, **attributes)
  end

  # Returns the raw token, which is only ever available at creation time.
  def issue_invitation(organization:, **options)
    _invitation, raw_token = Invitation.issue!(organization: organization, **options)
    raw_token
  end

  def minimum_profile_attributes(**overrides)
    {
      display_name: "Alex Morgan",
      country: "United States",
      state_region: "MA",
      career_goal: "Build a portfolio that gets me hired",
      current_role_term: role_term("data_analyst"),
      experience_level: "intermediate",
      target_role_term: role_term("software_engineer")
    }.merge(overrides)
  end

  # Request payload shape for both onboarding endpoints.
  def minimum_profile_payload(**overrides)
    {
      display_name: "Alex Morgan",
      country: "United States",
      state_region: "MA",
      career_goal: "Build a portfolio that gets me hired",
      current_role_term_id: role_term("data_analyst").id,
      experience_level: "intermediate",
      target_role_term_id: role_term("software_engineer").id
    }.merge(overrides)
  end

  def independent_onboarding_payload(**overrides)
    minimum_profile_payload(age_attested: true, terms_accepted: true, **overrides)
  end

  def organization_payload(**overrides)
    {
      name: "STEM Forward",
      structure_term_id: structure_term.id,
      country: "United States",
      state_region: "MA",
      primary_goal_term_id: goal_term.id
    }.merge(overrides)
  end
end

RSpec.configure do |config|
  config.include IdentityFixtures
end
