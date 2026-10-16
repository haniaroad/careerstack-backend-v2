# frozen_string_literal: true

module Profiles
  class ClearLegacyImageUrls
    def self.call
      Profile.where.not(image_url: nil).update_all(image_url: nil, updated_at: Time.current)
    end
  end
end
