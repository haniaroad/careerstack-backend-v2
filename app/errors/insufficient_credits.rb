# frozen_string_literal: true

class InsufficientCredits < DomainError
  def initialize(message = "Insufficient credits", remaining: 0)
    super(message, code: "insufficient_credits", status: :unprocessable_entity)
    @remaining = remaining
  end

  attr_reader :remaining
end
