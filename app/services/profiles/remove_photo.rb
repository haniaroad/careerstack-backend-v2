# frozen_string_literal: true

module Profiles
  class RemovePhoto
    def self.call(user:)
      profile = user.profile
      raise DomainError.new("Profile not found", code: "not_found", status: :not_found) if profile.nil?

      profile.profile_photo.purge if profile.profile_photo.attached?
      profile.update!(image_url: nil)
      profile
    end
  end
end
