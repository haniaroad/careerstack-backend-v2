# frozen_string_literal: true

module Invitations
  # Resolves a raw invitation token. An unknown, expired, or already-accepted
  # token produces the same response so a caller cannot probe for valid tokens.
  module Lookup
    INVALID_CODE = "invalid_invitation"
    INVALID_MESSAGE = "Invitation is invalid, expired, or already used"

    def self.usable!(raw_token)
      invitation = Invitation.find_by_raw_token(raw_token)
      raise Error.new(INVALID_MESSAGE, code: INVALID_CODE) unless invitation&.usable?

      invitation
    end
  end
end
