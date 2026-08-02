# frozen_string_literal: true

Sentry.init do |config|
  config.dsn = ENV["SENTRY_DSN"].presence
  config.breadcrumbs_logger = [ :active_support_logger, :http_logger ]
  config.traces_sample_rate = 0.0
  config.enabled_environments = %w[production staging]
  config.environment = ENV.fetch("SENTRY_ENVIRONMENT", ENV.fetch("RAILS_ENV", "development"))
end
