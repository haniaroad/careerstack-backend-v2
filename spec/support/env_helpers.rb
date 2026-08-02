# frozen_string_literal: true

# Temporarily overrides ENV for a block and always restores the previous value.
# A nil value unsets the variable for the duration.
module EnvHelpers
  def with_env(overrides)
    previous = overrides.keys.to_h { |key| [ key.to_s, ENV[key.to_s] ] }
    overrides.each { |key, value| write_env(key.to_s, value) }
    yield
  ensure
    previous.each { |key, value| write_env(key, value) }
  end

  private

  def write_env(key, value)
    value.nil? ? ENV.delete(key) : ENV[key] = value
  end
end

RSpec.configure do |config|
  config.include EnvHelpers
end
