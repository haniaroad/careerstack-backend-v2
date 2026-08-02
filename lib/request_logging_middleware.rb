# frozen_string_literal: true

class RequestLoggingMiddleware
  def initialize(app)
    @app = app
  end

  def call(env)
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    status, headers, body = @app.call(env)
    duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round(1)

    payload = {
      event: "request",
      method: env["REQUEST_METHOD"],
      path: env["PATH_INFO"],
      status: status,
      duration_ms: duration_ms,
      request_id: env["careerstack.request_id"] || env["action_dispatch.request_id"]
    }

    Rails.logger.info(payload.to_json)
    [ status, headers, body ]
  end
end
