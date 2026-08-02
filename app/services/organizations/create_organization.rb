# frozen_string_literal: true

module Organizations
  # Self-serve organization creation. The creator becomes the first admin, the
  # organization gets its workspace, and three pooled trial credits are granted
  # once per verified adult ever. No personal credit is consumed.
  class CreateOrganization
    REQUIRED_FIELDS = %i[name country state_region].freeze

    TEXT_FIELDS = %i[name country state_region].freeze

    OPTIONAL_FIELDS = %i[
      structure_term_id structure_other primary_goal_term_id primary_goal_other
      website logo_url expected_participant_range
    ].freeze

    Result = Struct.new(:organization, :workspace, :membership, :trial_granted, keyword_init: true)

    def self.call(user:, params:)
      new(user: user, params: params).call
    end

    def initialize(user:, params:)
      @user = user
      @params = params.to_h.with_indifferent_access
    end

    def call
      authorize!
      attributes = organization_attributes
      validate!(attributes)

      ActiveRecord::Base.transaction do
        organization = Organization.create!(attributes)
        workspace = Workspaces::EnsureOrganization.call(organization: organization)
        membership = OrganizationMembership.create!(
          organization: organization,
          user: @user,
          role: "admin"
        )
        trial_granted = Credits::GrantOrganizationTrial.call(user: @user, organization: organization)

        Result.new(
          organization: organization,
          workspace: workspace,
          membership: membership,
          trial_granted: trial_granted
        )
      end
    end

    private

    def authorize!
      raise Error.new("Complete onboarding before creating an organization", code: "onboarding_required") if @user.pending_onboarding?

      # Minors and unknown-age users cannot own an organization.
      unless @user.adult?
        raise Error.new(
          "Only verified adults can create an organization",
          code: "forbidden",
          status: :forbidden
        )
      end
    end

    def organization_attributes
      attributes = TEXT_FIELDS.index_with { |field| @params[field].to_s.strip }
      OPTIONAL_FIELDS.each { |field| attributes[field] = @params[field].presence }
      attributes[:timezone] = timezone
      attributes
    end

    def timezone
      candidate = @params[:timezone].presence || "UTC"
      raise Error, "timezone is not a recognized IANA timezone" if ActiveSupport::TimeZone[candidate].nil?

      candidate
    end

    def validate!(attributes)
      REQUIRED_FIELDS.each do |field|
        raise Error, "#{field} is required" if attributes[field].blank?
      end

      validate_choice!(attributes, :structure, "organization_structures", "structure")
      validate_choice!(attributes, :primary_goal, "organization_goals", "primary goal")
    end

    # Either a controlled term or free text for the Other option.
    def validate_choice!(attributes, prefix, taxonomy_key, label)
      term_id = attributes[:"#{prefix}_term_id"]
      other = attributes[:"#{prefix}_other"]
      raise Error, "#{label} is required" if term_id.blank? && other.blank?
      return if term_id.blank?
      return if term_ids(taxonomy_key).include?(term_id)

      raise Error, "#{label} is not a known option"
    end

    def term_ids(taxonomy_key)
      @term_ids ||= {}
      @term_ids[taxonomy_key] ||=
        TaxonomyTerm.joins(:taxonomy).where(taxonomies: { key: taxonomy_key }).pluck(:id)
    end
  end
end
