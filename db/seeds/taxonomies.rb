# frozen_string_literal: true

TaxonomySeeder.call

Rails.logger.info("Seeded #{Taxonomy.count} taxonomies with #{TaxonomyTerm.count} terms")
