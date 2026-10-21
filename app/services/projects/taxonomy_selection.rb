# frozen_string_literal: true

module Projects
  # Shared skill and role labels. New values must come from the taxonomies.
  # A skill already stored on the project may be saved again. A team role may
  # include one short custom string when Other is also selected.
  module TaxonomySelection
    OTHER = "Other"
    MAX_CUSTOM_ROLE = 80

    module_function

    def skill_labels
      labels_for("skills")
    end

    def role_labels
      labels_for("roles")
    end

    def validate_skills!(incoming, existing: [])
      values = clean(incoming)
      allowed = skill_labels
      legacy = Array(existing).map { |value| value.to_s.strip }
      unknown = values.reject { |skill| allowed.include?(skill) || legacy.include?(skill) }
      if unknown.any?
        raise DomainError.new("Unknown skill: #{unknown.first}", code: "validation_error")
      end

      values
    end

    def validate_roles!(incoming, existing: [])
      values = clean(incoming)
      raise DomainError.new("At least one role is required", code: "validation_error") if values.empty?

      allowed = role_labels
      legacy = Array(existing).map { |value| value.to_s.strip }
      unknown = values.reject { |role| allowed.include?(role) || legacy.include?(role) }
      if unknown.size > 1
        raise DomainError.new("Only one custom role is allowed", code: "validation_error")
      end
      if unknown.any?
        custom = unknown.first
        unless values.include?(OTHER)
          raise DomainError.new("Unknown role: #{custom}", code: "validation_error")
        end
        if custom.length > MAX_CUSTOM_ROLE
          raise DomainError.new("Custom role is too long", code: "validation_error")
        end
      end

      values
    end

    def labels_for(taxonomy_key)
      Taxonomy.find_by(key: taxonomy_key)&.taxonomy_terms&.order(:position)&.pluck(:label) || []
    end

    def clean(values)
      Array(values).map { |value| value.to_s.strip }.reject(&:blank?).uniq
    end
    private_class_method :labels_for, :clean
  end
end
