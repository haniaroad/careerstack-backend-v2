# frozen_string_literal: true

module CorsOrigins
  module_function

  def list
    ENV.fetch("CORS_ORIGINS", "http://localhost:5173").split(",").map(&:strip).reject(&:blank?)
  end
end
