# frozen_string_literal: true

class UpgradeRequestSerializer
  def self.call(request)
    {
      id: request.id,
      organization_id: request.organization_id,
      expected_participants: request.expected_participants,
      expected_projects_or_cohorts: request.expected_projects_or_cohorts,
      timeline: request.timeline,
      notes: request.notes,
      status: request.status,
      updated_at: request.updated_at
    }
  end
end
