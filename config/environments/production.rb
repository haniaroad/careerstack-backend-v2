require "active_support/core_ext/integer/time"

Rails.application.configure do
  config.enable_reloading = false
  config.eager_load = true
  config.consider_all_requests_local = false
  config.public_file_server.enabled = false

  config.active_support.report_deprecations = false
  config.log_tags = [ :request_id ]
  config.log_level = ENV.fetch("RAILS_LOG_LEVEL", "info")
  config.logger = ActiveSupport::Logger.new($stdout)
    .tap { |logger| logger.formatter = config.log_formatter }
    .then { |logger| ActiveSupport::TaggedLogging.new(logger) }

  config.action_mailer.perform_caching = false
  config.i18n.fallbacks = true
  config.active_record.dump_schema_after_migration = false
  config.active_record.attributes_for_inspect = [ :id ]

  config.require_master_key = false

  missing = %w[SECRET_KEY_BASE DATABASE_URL].reject { |key| ENV[key].present? }
  if missing.any?
    raise "Missing required configuration: #{missing.join(', ')}"
  end
end
