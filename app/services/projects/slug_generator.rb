# frozen_string_literal: true

module Projects
  # Builds a stable lowercase kebab-case slug from a project title, appending a
  # short random suffix when the base collides with an existing slug.
  class SlugGenerator
    SUFFIX_LENGTH = 4
    MAX_ATTEMPTS = 12

    def self.call(title:, exclude_project_id: nil)
      new(title: title, exclude_project_id: exclude_project_id).call
    end

    def initialize(title:, exclude_project_id: nil)
      @title = title.to_s
      @exclude_project_id = exclude_project_id
    end

    def call
      base = parameterize(@title)
      base = "project" if base.blank?

      candidate = base
      return candidate unless taken?(candidate)

      MAX_ATTEMPTS.times do
        candidate = "#{base}-#{SecureRandom.alphanumeric(SUFFIX_LENGTH).downcase}"
        return candidate unless taken?(candidate)
      end

      "#{base}-#{SecureRandom.uuid.split("-").first}"
    end

    private

    def parameterize(value)
      value.unicode_normalize(:nfkd)
           .gsub(/[^\x00-\x7F]/, "")
           .downcase
           .gsub(/[^a-z0-9]+/, "-")
           .gsub(/\A-+|-+\z/, "")
           .slice(0, 48)
           .to_s
           .gsub(/-+\z/, "")
    end

    def taken?(slug)
      scope = Project.where(slug: slug)
      scope = scope.where.not(id: @exclude_project_id) if @exclude_project_id.present?
      scope.exists?
    end
  end
end
