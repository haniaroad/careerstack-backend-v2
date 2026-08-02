# frozen_string_literal: true

module Workspaces
  # Grants the one Personal workspace an adult is entitled to. Returns nil for
  # minors and unknown-age users, who must stay organization-private.
  class EnsurePersonal
    def self.call(user:)
      new(user: user).call
    end

    def initialize(user:)
      @user = user
    end

    def call
      return @user.personal_workspace if @user.personal_workspace
      return nil unless @user.adult?

      workspace = Workspace.create!(kind: "personal", name: "Personal", owner_user: @user)
      attributes = { personal_workspace_id: workspace.id }
      attributes[:active_workspace_id] = workspace.id if @user.active_workspace_id.blank?
      @user.update!(attributes)
      workspace
    rescue ActiveRecord::RecordNotUnique
      @user.reload.personal_workspace
    end
  end
end
