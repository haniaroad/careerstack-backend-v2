# frozen_string_literal: true

module Organizations
  class StartOffboarding
    def self.call(organization:)
      new(organization: organization).call
    end

    def initialize(organization:)
      @organization = organization
    end

    def call
      raise Error, "Organization is already disabled" if @organization.workspace_disabled?
      return @organization if @organization.offboarding_readonly?

      started = Time.current
      @organization.update!(
        workspace_status: Organization::WORKSPACE_OFFBOARDING,
        offboarding_started_at: started,
        offboarding_ends_on: started.to_date + Organization::OFFBOARDING_DAYS
      )
      @organization
    end
  end
end
