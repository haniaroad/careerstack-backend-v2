# frozen_string_literal: true

# Idempotent in every environment: taxonomy terms keep stable IDs, so re-running
# updates labels and ordering without reassigning identifiers.
require_relative "seeds/taxonomies"
