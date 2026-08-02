# frozen_string_literal: true

class WorkspaceSerializer
  def self.call(workspace)
    return nil if workspace.nil?

    {
      id: workspace.id,
      kind: workspace.kind,
      name: workspace.name,
      organization_id: workspace.organization_id
    }
  end
end
