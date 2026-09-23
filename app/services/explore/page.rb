# frozen_string_literal: true

module Explore
  module Page
    MAX_PER_PAGE = 20

    def self.parse(page:, per_page:)
      number = page.to_i
      number = 1 if number < 1
      size = per_page.to_i
      size = MAX_PER_PAGE if size < 1 || size > MAX_PER_PAGE
      [ number, size ]
    end
  end
end
