# frozen_string_literal: true

module Profiles
  class ConfirmVisibility
    def self.call(user:, decision:)
      new(user: user, decision: decision).call
    end

    def initialize(user:, decision:)
      @user = user
      @decision = decision.to_s
    end

    def call
      unless @user.adult?
        raise DomainError.new("Only adults can change public visibility", code: "forbidden", status: :forbidden)
      end

      preference = @user.age_visibility_preference || @user.create_age_visibility_preference!

      case @decision
      when "confirm"
        preference.confirm_public_identity!
      when "reverse"
        preference.reverse_public_identity!
      else
        raise DomainError.new("decision must be confirm or reverse", code: "validation_error")
      end

      @user.reload
    end
  end
end
