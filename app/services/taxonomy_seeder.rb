# frozen_string_literal: true

# Seeds the controlled taxonomies that back profile and organization pickers.
#
# Term IDs are hard-coded so that a term keeps the same identifier in every
# environment. Clients may cache them and profile rows reference them by FK, so
# an existing ID must never be reassigned to a different key.
class TaxonomySeeder
  ROLES = [
    { id: "11111111-1111-4111-8111-111111111007", key: "frontend_developer", label: "Frontend developer" },
    { id: "11111111-1111-4111-8111-111111111008", key: "backend_developer", label: "Backend developer" },
    { id: "11111111-1111-4111-8111-111111111009", key: "full_stack_developer", label: "Full stack developer" },
    { id: "11111111-1111-4111-8111-111111111010", key: "mobile_app_developer", label: "Mobile app developer" },
    { id: "11111111-1111-4111-8111-111111111001", key: "software_engineer", label: "Software engineer" },
    { id: "11111111-1111-4111-8111-111111111002", key: "data_analyst", label: "Data analyst" },
    { id: "11111111-1111-4111-8111-111111111011", key: "data_scientist", label: "Data scientist" },
    { id: "11111111-1111-4111-8111-111111111006", key: "ai_ml_engineer", label: "AI/ML engineer" },
    { id: "11111111-1111-4111-8111-111111111012", key: "machine_learning_engineer", label: "Machine learning engineer" },
    { id: "11111111-1111-4111-8111-111111111003", key: "product_designer", label: "UI/UX designer" },
    { id: "11111111-1111-4111-8111-111111111004", key: "product_manager", label: "Product manager" },
    { id: "11111111-1111-4111-8111-111111111013", key: "quality_assurance", label: "Quality assurance" },
    { id: "11111111-1111-4111-8111-111111111005", key: "cybersecurity_analyst", label: "Cybersecurity analyst" },
    { id: "11111111-1111-4111-8111-111111111014", key: "cloud_engineer", label: "Cloud engineer" },
    { id: "11111111-1111-4111-8111-111111111015", key: "devops_engineer", label: "DevOps engineer" },
    { id: "11111111-1111-4111-8111-111111111016", key: "game_developer", label: "Game developer" },
    { id: "11111111-1111-4111-8111-111111111017", key: "business_analyst", label: "Business analyst" },
    { id: "11111111-1111-4111-8111-111111111018", key: "project_manager", label: "Project manager" },
    { id: "11111111-1111-4111-8111-111111111019", key: "scrum_master", label: "Scrum master" },
    { id: "11111111-1111-4111-8111-111111111020", key: "content_writer", label: "Content writer" },
    { id: "11111111-1111-4111-8111-111111111021", key: "digital_marketer", label: "Digital marketer" },
    { id: "11111111-1111-4111-8111-111111111022", key: "social_media_marketer", label: "Social media marketer" },
    { id: "11111111-1111-4111-8111-111111111023", key: "videographer", label: "Videographer" },
    { id: "11111111-1111-4111-8111-111111111024", key: "video_editor", label: "Video editor" },
    { id: "11111111-1111-4111-8111-111111111099", key: "other", label: "Other", is_other: true }
  ].freeze

  SKILLS = [
    { id: "55555555-5555-4555-8555-555555555001", key: "web_development", label: "Web development" },
    { id: "55555555-5555-4555-8555-555555555002", key: "mobile_development", label: "Mobile development" },
    { id: "55555555-5555-4555-8555-555555555003", key: "data_science", label: "Data science" },
    { id: "55555555-5555-4555-8555-555555555004", key: "data_analysis", label: "Data analysis" },
    { id: "55555555-5555-4555-8555-555555555005", key: "machine_learning", label: "Machine learning" },
    { id: "55555555-5555-4555-8555-555555555006", key: "artificial_intelligence", label: "Artificial intelligence" },
    { id: "55555555-5555-4555-8555-555555555007", key: "cybersecurity", label: "Cybersecurity" },
    { id: "55555555-5555-4555-8555-555555555008", key: "cloud_computing", label: "Cloud computing" },
    { id: "55555555-5555-4555-8555-555555555009", key: "devops", label: "DevOps" },
    { id: "55555555-5555-4555-8555-555555555010", key: "ui_ux_design", label: "UI/UX design" },
    { id: "55555555-5555-4555-8555-555555555011", key: "quality_assurance", label: "Quality assurance" },
    { id: "55555555-5555-4555-8555-555555555012", key: "product_management", label: "Product management" },
    { id: "55555555-5555-4555-8555-555555555013", key: "project_management", label: "Project management" },
    { id: "55555555-5555-4555-8555-555555555014", key: "business_analysis", label: "Business analysis" },
    { id: "55555555-5555-4555-8555-555555555015", key: "content_writing", label: "Content writing" },
    { id: "55555555-5555-4555-8555-555555555016", key: "technical_writing", label: "Technical writing" },
    { id: "55555555-5555-4555-8555-555555555017", key: "digital_marketing", label: "Digital marketing" },
    { id: "55555555-5555-4555-8555-555555555018", key: "video_production", label: "Video production" },
    { id: "55555555-5555-4555-8555-555555555019", key: "no_code", label: "No-code" },
    { id: "55555555-5555-4555-8555-555555555020", key: "low_code", label: "Low-code" },
    { id: "55555555-5555-4555-8555-555555555021", key: "accessibility", label: "Accessibility" },
    { id: "55555555-5555-4555-8555-555555555099", key: "other", label: "Other", is_other: true }
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
    "organization_goals" => { name: "Organization goals", terms: ORGANIZATION_GOALS },
    "skills" => { name: "Skills", terms: SKILLS }
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
