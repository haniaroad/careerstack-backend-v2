# frozen_string_literal: true

class InboxItemSerializer
  def self.call(item)
    {
      id: item.id,
      category: item.category,
      related_id: item.related_id,
      project_id: item.project_id,
      project_title: item.project_title,
      title: item.title,
      description: item.description,
      status_label: item.status_label,
      urgency: item.urgency,
      is_overdue: item.is_overdue,
      cta_label: item.cta_label,
      created_at: item.created_at,
      payload: item.payload
    }
  end
end
