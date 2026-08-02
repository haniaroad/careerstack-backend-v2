# frozen_string_literal: true

module Workspaces
  # Every organization has exactly one workspace, enforced by a partial unique
  # index. Concurrent callers can both miss the read, so a lost race falls back
  # to the row the winner inserted.
  class EnsureOrganization
    def self.call(organization:)
      new(organization: organization).call
    end

    def initialize(organization:)
      @organization = organization
    end

    def call
      existing = @organization.workspace
      return existing if existing

      Workspace.create!(kind: "organization", name: @organization.name, organization: @organization)
    rescue ActiveRecord::RecordNotUnique
      @organization.reload.workspace
    end
  end
end
