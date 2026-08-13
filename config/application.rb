require_relative "boot"
require_relative "../lib/correlation_id_middleware"
require_relative "../lib/request_logging_middleware"

require "rails"
require "active_model/railtie"
require "active_job/railtie"
require "active_record/railtie"
require "active_storage/engine"
require "action_controller/railtie"
require "action_mailer/railtie"
require "action_view/railtie"
require "action_cable/engine"

Bundler.require(*Rails.groups)

module CareerstackBackendV2
  class Application < Rails::Application
    config.load_defaults 8.0
    config.autoload_lib(ignore: %w[assets tasks])
    config.api_only = true

    config.middleware.insert_before 0, CorrelationIdMiddleware
    config.middleware.use RequestLoggingMiddleware
    config.middleware.use Rack::Attack
    config.active_job.queue_adapter = :solid_queue
    config.solid_queue.connects_to = { database: { writing: :queue } }
    config.log_tags = [ :request_id ]
  end
end
