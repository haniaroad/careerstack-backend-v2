# frozen_string_literal: true

module Profiles
  # Resolves whether a user's identity may be shown as a public adult profile.
  class Visibility
    PUBLIC_ADULT = "public_adult"
    RESTRICTED = "restricted"

    def self.code_for(user)
      new(user).code
    end

    def self.public_adult?(user)
      code_for(user) == PUBLIC_ADULT
    end

    def initialize(user)
      @user = user
    end

    def code
      return RESTRICTED if @user.nil?
      return RESTRICTED if @user.suspended?
      return RESTRICTED unless @user.adult?
      return RESTRICTED unless @user.public_identity_visible?

      PUBLIC_ADULT
    end
  end
end
