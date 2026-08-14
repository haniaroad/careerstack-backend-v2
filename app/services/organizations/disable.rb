# frozen_string_literal: true

module Organizations
  class Disable
    def self.call(organization:)
      new(organization: organization).call
    end

    def initialize(organization:)
      @organization = organization
    end

    def call
      return @organization if @organization.workspace_disabled?

      ActiveRecord::Base.transaction do
        @organization.update!(workspace_status: Organization::WORKSPACE_DISABLED)
        workspace = @organization.workspace
        if workspace
          User.where(active_workspace_id: workspace.id).find_each do |user|
            fallback = user.personal_workspace
            user.update!(active_workspace_id: fallback&.id)
          end
        end
      end
      @organization
    end
  end
end
