# frozen_string_literal: true

require "rails_helper"

RSpec.describe Workspace do
  let(:user) { create_user(email: "owner@example.com", age_status: AgeStatusCalculator::ADULT) }

  it "requires an owner for a personal workspace" do
    workspace = Workspace.new(kind: "personal", name: "Personal")

    expect(workspace).not_to be_valid
    expect(workspace.errors[:owner_user]).to be_present
  end

  it "rejects a personal workspace that also names an organization" do
    workspace = Workspace.new(kind: "personal", name: "Personal", owner_user: user, organization: create_organization)

    expect(workspace).not_to be_valid
  end

  it "requires an organization for an organization workspace" do
    workspace = Workspace.new(kind: "organization", name: "Org")

    expect(workspace).not_to be_valid
    expect(workspace.errors[:organization]).to be_present
  end

  it "rejects an unknown kind" do
    expect(Workspace.new(kind: "team", name: "Team", owner_user: user)).not_to be_valid
  end

  it "allows only one personal workspace per owner" do
    Workspace.create!(kind: "personal", name: "Personal", owner_user: user)

    expect { Workspace.create!(kind: "personal", name: "Second", owner_user: user) }
      .to raise_error(ActiveRecord::RecordNotUnique)
  end

  it "allows only one workspace per organization" do
    organization = create_organization

    expect { Workspace.create!(kind: "organization", name: "Duplicate", organization: organization) }
      .to raise_error(ActiveRecord::RecordNotUnique)
  end

  describe "Workspaces::EnsurePersonal" do
    it "returns nil for a minor" do
      minor = create_user(email: "minor@example.com", age_status: AgeStatusCalculator::MINOR)

      expect(Workspaces::EnsurePersonal.call(user: minor)).to be_nil
      expect(minor.reload.personal_workspace).to be_nil
    end

    it "creates the workspace once and reuses it afterwards" do
      first = Workspaces::EnsurePersonal.call(user: user)
      second = Workspaces::EnsurePersonal.call(user: user.reload)

      expect(second).to eq(first)
      expect(Workspace.where(owner_user: user).count).to eq(1)
    end

    it "sets the new workspace active when nothing else was active" do
      workspace = Workspaces::EnsurePersonal.call(user: user)

      expect(user.reload.active_workspace_id).to eq(workspace.id)
    end

    it "leaves an existing active workspace in place" do
      organization = create_organization
      create_membership(organization: organization, user: user)
      user.update!(active_workspace_id: organization.workspace.id)

      Workspaces::EnsurePersonal.call(user: user)

      expect(user.reload.active_workspace_id).to eq(organization.workspace.id)
    end
  end

  describe "Workspaces::EnsureOrganization" do
    it "is idempotent" do
      organization = create_organization
      existing = organization.workspace

      expect(Workspaces::EnsureOrganization.call(organization: organization.reload)).to eq(existing)
      expect(Workspace.where(organization: organization).count).to eq(1)
    end
  end
end
