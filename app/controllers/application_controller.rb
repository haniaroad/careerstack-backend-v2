# frozen_string_literal: true

class ApplicationController < ActionController::API
  include ErrorEnvelope
  include Authenticatable

  rescue_from ActiveRecord::RecordNotFound do |_error|
    render_error(code: "not_found", message: "Resource not found", status: :not_found)
  end
end
