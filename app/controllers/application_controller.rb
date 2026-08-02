# frozen_string_literal: true

class ApplicationController < ActionController::API
  include ErrorEnvelope
  include Authenticatable

  rescue_from ActiveRecord::RecordNotFound do |_error|
    render_error(code: "not_found", message: "Resource not found", status: :not_found)
  end

  rescue_from ActionController::ParameterMissing do |error|
    render_error(
      code: "validation_error",
      message: "#{error.param} is required",
      status: :unprocessable_entity
    )
  end

  rescue_from ActiveRecord::RecordInvalid do |error|
    render_error(
      code: "validation_error",
      message: error.record.errors.full_messages.to_sentence,
      status: :unprocessable_entity
    )
  end
end
