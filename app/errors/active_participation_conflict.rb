# frozen_string_literal: true

class ActiveParticipationConflict < DomainError
  def initialize(message = "You already have an active project participation")
    super(message, code: "active_participation_conflict", status: :unprocessable_entity)
  end
end
