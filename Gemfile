source "https://rubygems.org"

gem "rails", "~> 8.0.2"
gem "pg", "~> 1.1"
gem "puma", ">= 5.0"
gem "bootsnap", require: false
gem "tzinfo-data", platforms: %i[ windows jruby ]

# Platform foundation
gem "rack-cors"
gem "solid_queue"
gem "sentry-ruby"
gem "sentry-rails"

# Firebase ID token verification (RS256 via Google JWKS)
gem "jwt"

# Personal credit pack Checkout + webhooks
gem "stripe", "~> 13.0"

# Anonymous public API rate limiting
gem "rack-attack"

group :development, :test do
  gem "debug", platforms: %i[ mri windows ], require: "debug/prelude"
  gem "brakeman", require: false
  gem "bundler-audit", require: false
  gem "rubocop-rails-omakase", require: false
  gem "rspec-rails", "~> 7.0"
end

group :test do
  gem "rack-test"
end

# File evidence uploads + AI review extractors
gem "image_processing", "~> 1.2"
gem "pdf-reader", "~> 2.12"
gem "rubyzip", "~> 2.3"
