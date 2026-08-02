# frozen_string_literal: true

class CorrelationIdMiddleware
  HEADER = "X-Request-Id"
  ENV_KEY = "action_dispatch.request_id"

  def initialize(app)
    @app = app
  end

  def call(env)
    request_id = extract_or_generate(env)
    env[ENV_KEY] = request_id
    env["careerstack.request_id"] = request_id

    status, headers, body = @app.call(env)
    headers[HEADER] = request_id
    [ status, headers, body ]
  end

  private

  def extract_or_generate(env)
    incoming = env["HTTP_X_REQUEST_ID"].to_s.strip
    incoming.presence || SecureRandom.uuid
  end
end
