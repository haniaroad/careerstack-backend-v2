# frozen_string_literal: true

module ErrorEnvelope
  extend ActiveSupport::Concern

  private

  def render_error(code:, message:, status:)
    render json: {
      error: {
        code: code,
        message: message,
        request_id: request.request_id
      }
    }, status: status
  end
end
