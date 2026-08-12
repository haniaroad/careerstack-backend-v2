# frozen_string_literal: true

class Rack::Attack
  ### Configure Cache ###
  # Uses Rails.cache; memory store is fine for local/single-instance, Redis in multi-instance.

  throttle("public_api/ip", limit: 60, period: 1.minute) do |req|
    req.ip if req.path.start_with?("/api/v1/public/")
  end

  self.throttled_responder = lambda do |_request|
    [
      429,
      { "Content-Type" => "application/json" },
      [ { error: { code: "rate_limited", message: "Too many requests" } }.to_json ]
    ]
  end
end
