# frozen_string_literal: true

class NotificationPreferenceSerializer
  def self.list(user)
    NotificationPreference.ensure_defaults!(user)
    Notifications::Catalog::CATEGORIES.map do |id, meta|
      preference = user.notification_preferences.find_by(category: id)
      {
        id: id,
        label: meta[:label],
        description: meta[:description],
        tier: meta[:tier],
        can_disable: meta[:can_disable],
        email_enabled: preference&.email_enabled != false,
        digest_cadence: preference&.digest_cadence
      }
    end
  end
end
