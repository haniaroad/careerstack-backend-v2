# frozen_string_literal: true

# Configure the Stripe SDK from ENV once the app has finished booting.
# Local webhook forwarding: stripe listen --forward-to localhost:3000/api/v1/stripe/webhooks
Rails.application.config.after_initialize do
  begin
    require "stripe"
    Billing::StripeConfig.apply!
  rescue LoadError
    Rails.logger.warn("stripe gem is not installed; personal Checkout is unavailable until bundle install")
  end
end
