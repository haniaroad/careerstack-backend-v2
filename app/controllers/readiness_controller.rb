# frozen_string_literal: true

class ReadinessController < ApplicationController
  def show
    ActiveRecord::Base.connection.execute("SELECT 1")
    render json: { status: "ready" }, status: :ok
  rescue ActiveRecord::ActiveRecordError, PG::Error => e
    render json: { status: "not_ready", reason: e.class.name }, status: :service_unavailable
  end
end
