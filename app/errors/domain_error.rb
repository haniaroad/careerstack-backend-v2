# frozen_string_literal: true

# Base class for expected business-rule rejections raised by services.
#
# Carrying the envelope code and HTTP status on the exception lets a single
# rescue in Api::V1::BaseController translate any of them, so controllers do not
# repeat error mapping.
class DomainError < StandardError
  DEFAULT_CODE = "validation_error"

  attr_reader :code, :status

  def initialize(message, code: DEFAULT_CODE, status: :unprocessable_entity)
    super(message)
    @code = code
    @status = status
  end
end
