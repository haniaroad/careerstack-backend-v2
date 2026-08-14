# frozen_string_literal: true

class OrganizationSerializer
  def self.call(organization)
    {
      id: organization.id,
      name: organization.name,
      timezone: organization.timezone,
      logo_url: organization.logo_url,
      workspace_id: organization.workspace&.id,
      workspace_status: organization.workspace_status,
      offboarding_started_at: organization.offboarding_started_at,
      offboarding_ends_on: organization.offboarding_ends_on
    }
  end
end
