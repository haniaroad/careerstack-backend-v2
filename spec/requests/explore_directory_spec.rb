# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Explore directory", type: :request do
  def directory_project!(creator:, workspace:, title:, visibility: "public", status: "active", mode: "team", program: nil, skills: [ "Facilitation" ])
    Project.create!(
      workspace: workspace,
      creator: creator,
      program: program,
      title: title,
      mode: mode,
      status: status,
      visibility: visibility,
      joining_mode: mode == "team" ? "instant" : nil,
      capacity: mode == "team" ? 3 : nil,
      roles_needed: mode == "team" ? [ "Designer" ] : [],
      skills: skills,
      ends_on: Date.current + 30
    )
  end

  def use_workspace!(user, workspace)
    user.update!(active_workspace: workspace)
  end

  it "lists public projects in Personal and hides private and other-org private projects" do
    viewer = create_onboarded_adult(email: "explore-viewer-#{SecureRandom.hex(3)}@example.com")
    owner = create_onboarded_adult(email: "explore-owner-#{SecureRandom.hex(3)}@example.com")
    public_project = directory_project!(creator: owner, workspace: owner.personal_workspace, title: "Public studio")
    directory_project!(creator: owner, workspace: owner.personal_workspace, title: "Private studio", visibility: "private")
    directory_project!(creator: owner, workspace: owner.personal_workspace, title: "Draft studio", status: "draft")

    organization = create_organization(name: "Hidden Org #{SecureRandom.hex(2)}")
    create_membership(organization: organization, user: owner, role: OrganizationMembership::ADMIN)
    program = create_program(organization: organization)
    directory_project!(
      creator: owner,
      workspace: organization.workspace,
      program: program,
      title: "Secret org project",
      visibility: "private"
    )

    get "/api/v1/explore/projects", headers: headers_for(viewer)
    expect(response).to have_http_status(:ok)
    titles = response.parsed_body["projects"].map { |row| row["title"] }
    expect(titles).to include(public_project.title)
    expect(titles).not_to include("Private studio", "Draft studio", "Secret org project")
    expect(response.parsed_body["per_page"]).to eq(20)
  end

  it "includes the active organization's private projects and applies the program filter" do
    viewer = create_onboarded_adult(email: "explore-member-#{SecureRandom.hex(3)}@example.com")
    organization = create_organization(name: "Visible Org #{SecureRandom.hex(2)}")
    membership = create_membership(organization: organization, user: viewer, role: OrganizationMembership::ADMIN)
    spring = create_program(organization: organization, name: "Spring")
    fall = create_program(organization: organization, name: "Fall")
    directory_project!(creator: viewer, workspace: organization.workspace, program: spring, title: "Spring private", visibility: "private")
    directory_project!(creator: viewer, workspace: organization.workspace, program: fall, title: "Fall private", visibility: "private")
    use_workspace!(viewer, organization.workspace)
    membership.update!(program_filter_program_id: spring.id)

    get "/api/v1/explore/projects", headers: headers_for(viewer)
    expect(response).to have_http_status(:ok)
    titles = response.parsed_body["projects"].map { |row| row["title"] }
    expect(titles).to eq([ "Spring private" ])
  end

  it "rejects unauthenticated directory reads" do
    get "/api/v1/explore/projects"
    expect(response).to have_http_status(:unauthorized)

    get "/api/v1/explore/people"
    expect(response).to have_http_status(:unauthorized)
  end

  it "lists searchable adults and drops minor, unknown, suspended, and age-up-pending identities" do
    viewer = create_onboarded_adult(email: "people-viewer-#{SecureRandom.hex(3)}@example.com")
    adult = create_onboarded_adult(email: "people-adult-#{SecureRandom.hex(3)}@example.com")
    adult.profile.update!(display_name: "Searchable Adult", state_region: "CA")
    minor = create_onboarded_adult(email: "people-minor-#{SecureRandom.hex(3)}@example.com")
    minor.update!(age_status: AgeStatusCalculator::MINOR, onboarding_path: "organization_invited")
    minor.profile.update!(display_name: "Hidden Minor")
    unknown = create_onboarded_adult(email: "people-unknown-#{SecureRandom.hex(3)}@example.com")
    unknown.update!(age_status: AgeStatusCalculator::UNKNOWN, onboarding_path: "organization_invited")
    unknown.profile.update!(display_name: "Hidden Unknown")
    suspended = create_onboarded_adult(email: "people-suspended-#{SecureRandom.hex(3)}@example.com")
    suspended.update!(status: User::SUSPENDED)
    suspended.profile.update!(display_name: "Hidden Suspended")
    pending = create_onboarded_adult(email: "people-pending-#{SecureRandom.hex(3)}@example.com")
    pending.update!(onboarding_path: "organization_invited")
    pending.age_visibility_preference.update!(public_identity_confirmed: false)
    pending.profile.update!(display_name: "Hidden Pending")

    get "/api/v1/explore/people", params: { name: "Hidden" }, headers: headers_for(viewer)
    expect(response).to have_http_status(:ok)
    names = response.parsed_body["people"].map { |row| row["display_name"] }
    expect(names).to eq([])
    expect(response.body).not_to include("Hidden Minor", "Hidden Unknown", "Hidden Suspended", "Hidden Pending")

    get "/api/v1/explore/people", params: { name: "Searchable", location: "CA" }, headers: headers_for(viewer)
    expect(response).to have_http_status(:ok)
    person = response.parsed_body["people"].find { |row| row["user_id"] == adult.id }
    expect(person["display_name"]).to eq("Searchable Adult")
    expect(person["slug"]).to eq(adult.profile.slug)
    expect(person).not_to have_key("email")
  end

  it "filters people by skill and shows an organization only for a public accomplishment" do
    viewer = create_onboarded_adult(email: "skill-viewer-#{SecureRandom.hex(3)}@example.com")
    member = create_onboarded_adult(email: "skill-member-#{SecureRandom.hex(3)}@example.com")
    member.profile.update!(display_name: "Skill Person")
    organization = create_organization(name: "Public STEM #{SecureRandom.hex(2)}")
    private_org = create_organization(name: "Quiet STEM #{SecureRandom.hex(2)}")
    create_membership(organization: organization, user: member, role: OrganizationMembership::PARTICIPANT)
    create_membership(organization: private_org, user: member, role: OrganizationMembership::PARTICIPANT)
    public_program = create_program(organization: organization)
    private_program = create_program(organization: private_org)
    public_project = directory_project!(
      creator: member,
      workspace: organization.workspace,
      program: public_program,
      title: "Public org work",
      visibility: "public",
      skills: [ "Facilitation" ]
    )
    directory_project!(
      creator: member,
      workspace: private_org.workspace,
      program: private_program,
      title: "Private org work",
      visibility: "private",
      skills: [ "Facilitation" ]
    )
    ProjectMembership.create!(
      project: public_project,
      user: member,
      role: ProjectMembership::ROLE_CREATOR,
      status: ProjectMembership::STATUS_ACTIVE
    )

    get "/api/v1/explore/people",
        params: { skill: "Facilitation", organization: organization.name },
        headers: headers_for(viewer)

    expect(response).to have_http_status(:ok)
    person = response.parsed_body["people"].find { |row| row["user_id"] == member.id }
    expect(person["skills"]).to include("Facilitation")
    expect(person["organizations"]).to eq([ organization.name ])
    expect(person["organizations"]).not_to include(private_org.name)
  end

  it "paginates directory lists with a bounded page size" do
    viewer = create_onboarded_adult(email: "page-viewer-#{SecureRandom.hex(3)}@example.com")
    2.times do |index|
      owner = create_onboarded_adult(email: "page-owner-#{index}-#{SecureRandom.hex(2)}@example.com")
      directory_project!(creator: owner, workspace: owner.personal_workspace, title: "Paged #{index}")
    end

    get "/api/v1/explore/projects", params: { per_page: 1, page: 1 }, headers: headers_for(viewer)
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body["projects"].length).to eq(1)
    expect(response.parsed_body["per_page"]).to eq(1)
    expect(response.parsed_body["total_count"]).to be >= 2

    get "/api/v1/explore/projects", params: { per_page: 500 }, headers: headers_for(viewer)
    expect(response.parsed_body["per_page"]).to eq(20)
  end

  it "returns eligible invite projects and blocks an active participant without consuming credit" do
    creator = create_onboarded_adult(email: "invite-creator-#{SecureRandom.hex(3)}@example.com")
    target = create_onboarded_adult(email: "invite-target-#{SecureRandom.hex(3)}@example.com")
    busy = create_onboarded_adult(email: "invite-busy-#{SecureRandom.hex(3)}@example.com")
    outsider = create_onboarded_adult(email: "invite-out-#{SecureRandom.hex(3)}@example.com")
    first = directory_project!(creator: creator, workspace: creator.personal_workspace, title: "Alpha team")
    second = directory_project!(creator: creator, workspace: creator.personal_workspace, title: "Beta team")
    organization = create_organization(name: "Invite Org #{SecureRandom.hex(2)}")
    create_membership(organization: organization, user: creator, role: OrganizationMembership::ADMIN)
    program = create_program(organization: organization)
    directory_project!(
      creator: creator,
      workspace: organization.workspace,
      program: program,
      title: "Org only team"
    )
    busy_project = directory_project!(creator: busy, workspace: busy.personal_workspace, title: "Busy project")
    ProjectMembership.create!(
      project: busy_project,
      user: busy,
      role: ProjectMembership::ROLE_PARTICIPANT,
      status: ProjectMembership::STATUS_ACTIVE,
      participant_role: "Designer",
      join_source: ProjectMembership::JOIN_SOURCE_INSTANT
    )

    get "/api/v1/explore/invite_options", params: { user_id: target.id }, headers: headers_for(creator)
    expect(response).to have_http_status(:ok)
    titles = response.parsed_body["eligible_projects"].map { |row| row["title"] }
    expect(titles).to eq([ "Alpha team", "Beta team" ])
    expect(response.parsed_body["unavailable"]).to be(false)

    get "/api/v1/explore/invite_options", params: { user_id: outsider.id }, headers: headers_for(creator)
    org_titles = response.parsed_body["eligible_projects"].map { |row| row["title"] }
    expect(org_titles).not_to include("Org only team")

    get "/api/v1/explore/invite_options", params: { user_id: creator.id }, headers: headers_for(creator)
    expect(response.parsed_body["eligible_projects"]).to eq([])

    credits_before = CreditLot.where(owner: creator).sum(:remaining)
    post "/api/v1/projects/#{first.id}/invitations",
         params: { invitee_id: target.id, requested_role: "Designer" },
         headers: headers_for(creator),
         as: :json
    expect(response).to have_http_status(:created)
    expect(CreditLot.where(owner: creator).sum(:remaining)).to eq(credits_before)
    expect(ProjectInvitation.where(project: first, invitee: target, status: "pending").count).to eq(1)

    get "/api/v1/explore/invite_options", params: { user_id: busy.id }, headers: headers_for(creator)
    expect(response.parsed_body["unavailable"]).to be(true)

    expect {
      post "/api/v1/projects/#{second.id}/invitations",
           params: { invitee_id: busy.id, requested_role: "Designer" },
           headers: headers_for(creator),
           as: :json
    }.not_to change(ProjectInvitation, :count)
    expect(response).to have_http_status(:conflict)
    expect(response.parsed_body["error"]["code"]).to eq("invitee_unavailable")

    post "/api/v1/projects/#{first.id}/invitations",
         params: { invitee_id: target.id, requested_role: "Designer" },
         as: :json
    expect(response).to have_http_status(:unauthorized)
  end
end
