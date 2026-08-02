# frozen_string_literal: true

# Seeds the controlled taxonomies that back profile and organization pickers.
#
# Term IDs are hard-coded so that a term keeps the same identifier in every
# environment. Clients may cache them and profile rows reference them by FK, so
# an existing ID must never be reassigned to a different key.
class TaxonomySeeder
  ROLES = [
    { id: "11111111-1111-4111-8111-111111111001", key: "software_engineer", label: "Software engineer" },
    { id: "11111111-1111-4111-8111-111111111002", key: "data_analyst", label: "Data analyst" },
    { id: "11111111-1111-4111-8111-111111111003", key: "product_designer", label: "Product designer" },
    { id: "11111111-1111-4111-8111-111111111004", key: "product_manager", label: "Product manager" },
    { id: "11111111-1111-4111-8111-111111111005", key: "cybersecurity_analyst", label: "Cybersecurity analyst" },
    { id: "11111111-1111-4111-8111-111111111006", key: "ai_ml_engineer", label: "AI/ML engineer" },
    { id: "11111111-1111-4111-8111-111111111099", key: "other", label: "Other", is_other: true }
  ].freeze

  EXPERIENCE_LEVELS = [
    { id: "22222222-2222-4222-8222-222222222001", key: "beginner", label: "Beginner" },
    { id: "22222222-2222-4222-8222-222222222002", key: "intermediate", label: "Intermediate" },
    { id: "22222222-2222-4222-8222-222222222003", key: "advanced", label: "Advanced" }
  ].freeze

  ORGANIZATION_STRUCTURES = [
    { id: "33333333-3333-4333-8333-333333333001", key: "nonprofit", label: "Nonprofit" },
    { id: "33333333-3333-4333-8333-333333333002", key: "school", label: "School" },
    { id: "33333333-3333-4333-8333-333333333003", key: "university", label: "University" },
    { id: "33333333-3333-4333-8333-333333333004", key: "bootcamp", label: "Bootcamp" },
    { id: "33333333-3333-4333-8333-333333333005", key: "company", label: "Company" },
    { id: "33333333-3333-4333-8333-333333333006", key: "government", label: "Government" },
    { id: "33333333-3333-4333-8333-333333333099", key: "other", label: "Other", is_other: true }
  ].freeze

  ORGANIZATION_GOALS = [
    { id: "44444444-4444-4444-8444-444444444001", key: "career_readiness", label: "Career readiness" },
    { id: "44444444-4444-4444-8444-444444444002", key: "portfolio_building", label: "Portfolio building" },
    { id: "44444444-4444-4444-8444-444444444003", key: "workforce_training", label: "Workforce training" },
    { id: "44444444-4444-4444-8444-444444444004", key: "community_program", label: "Community program" },
    { id: "44444444-4444-4444-8444-444444444099", key: "other", label: "Other", is_other: true }
  ].freeze

  DEFINITIONS = {
    "roles" => { name: "Roles", terms: ROLES },
    "experience_levels" => { name: "Experience levels", terms: EXPERIENCE_LEVELS },
    "organization_structures" => { name: "Organization structures", terms: ORGANIZATION_STRUCTURES },
    "organization_goals" => { name: "Organization goals", terms: ORGANIZATION_GOALS }
  }.freeze

  def self.call
    new.call
  end

  def call
    ActiveRecord::Base.transaction do
      DEFINITIONS.each do |taxonomy_key, definition|
        taxonomy = Taxonomy.find_or_initialize_by(key: taxonomy_key)
        taxonomy.name = definition[:name]
        taxonomy.save!

        prune_retired_terms(taxonomy, definition[:terms])
        upsert_terms(taxonomy, definition[:terms])
      end
    end
  end

  private

  def prune_retired_terms(taxonomy, definitions)
    retired = taxonomy.taxonomy_terms.where.not(id: definitions.pluck(:id))
    return if retired.empty?

    retired.destroy_all
  rescue ActiveRecord::InvalidForeignKey
    raise "Cannot retire taxonomy terms for '#{taxonomy.key}' that are still referenced by existing " \
          "records; migrate those references before changing the seed set."
  end

  def upsert_terms(taxonomy, definitions)
    pairs = definitions.map { |definition| [ definition, TaxonomyTerm.find_or_initialize_by(id: definition[:id]) ] }

    release_reassigned_keys(pairs)

    pairs.each_with_index do |(definition, term), position|
      term.taxonomy = taxonomy
      term.key = definition[:key]
      term.label = definition[:label]
      term.position = position
      term.is_other = definition.fetch(:is_other, false)
      term.save!
    end
  end

  # Keys are unique per taxonomy, so moving a key from one term to another would
  # collide while the previous holder still owns it. Parking those rows on a
  # throwaway key first lets the final assignment succeed in any order.
  def release_reassigned_keys(pairs)
    pairs.each do |definition, term|
      next if term.new_record?
      next if term.key == definition[:key]

      term.update_columns(key: "reseeding:#{term.id}")
    end
  end
end
