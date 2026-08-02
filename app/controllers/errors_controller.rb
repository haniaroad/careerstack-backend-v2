# frozen_string_literal: true

class ErrorsController < ApplicationController
  def not_found
    render_error(code: "not_found", message: "Resource not found", status: :not_found)
  end
end
