# frozen_string_literal: true

module FirstRunTips
  class Catalog
    MAX_KEYS = 5
    KEYS = %w[home my_work inbox profile].freeze

    if KEYS.size > MAX_KEYS
      raise "First-run tip catalog cannot exceed #{MAX_KEYS} keys"
    end

    ENTRIES = {
      "home" => {
        label: "Start here",
        standard: "Home shows your next action, including a first project in your Personal workspace if you still have a credit.",
        restricted: "Home shows the next action for this workspace."
      },
      "my_work" => {
        label: "Your work",
        standard: "My Work lists the projects and tasks you are part of, including personal projects.",
        restricted: "My Work lists the projects and tasks you are part of in this workspace."
      },
      "inbox" => {
        label: "Decisions",
        standard: "Inbox is where you respond to invitations and applications.",
        restricted: "Inbox is where you respond to invitations and applications."
      },
      "profile" => {
        label: "Your profile",
        standard: "Profile is your contribution record, and Settings is where you control what is public.",
        restricted: "Profile is your contribution record. Settings holds preferences for this account."
      }
    }.freeze

    def self.entry!(key)
      entry = ENTRIES[key.to_s]
      raise ActiveRecord::RecordNotFound if entry.nil?

      entry
    end

    def self.restricted?(user, key)
      case key.to_s
      when "home", "my_work"
        user.privacy_restricted? || user.personal_workspace_id.nil?
      when "profile"
        !user.public_identity_visible?
      else
        false
      end
    end
  end
end
