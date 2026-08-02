# frozen_string_literal: true

module Api
  module V1
    class TaxonomiesController < BaseController
      def index
        taxonomies = Taxonomy.includes(:taxonomy_terms).order(:key)

        render json: {
          taxonomies: taxonomies.map do |taxonomy|
            {
              key: taxonomy.key,
              name: taxonomy.name,
              terms: taxonomy.taxonomy_terms.sort_by(&:position).map do |term|
                { id: term.id, key: term.key, label: term.label, is_other: term.is_other }
              end
            }
          end
        }
      end
    end
  end
end
