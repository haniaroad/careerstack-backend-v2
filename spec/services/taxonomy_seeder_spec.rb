# frozen_string_literal: true

require "rails_helper"

RSpec.describe TaxonomySeeder do
  it "seeds all four controlled taxonomies" do
    expect(Taxonomy.pluck(:key)).to match_array(
      %w[roles experience_levels organization_structures organization_goals]
    )
  end

  it "is idempotent and keeps term ids stable" do
    before_ids = TaxonomyTerm.order(:id).pluck(:id)

    expect { described_class.call }.not_to change(TaxonomyTerm, :count)
    expect(TaxonomyTerm.order(:id).pluck(:id)).to eq(before_ids)
  end

  it "restores a label that drifted" do
    term = TaxonomyTerm.joins(:taxonomy).find_by!(taxonomies: { key: "roles" }, key: "software_engineer")
    term.update_columns(label: "Wrong label")

    described_class.call

    expect(term.reload.label).to eq("Software engineer")
  end

  it "orders terms with Other last" do
    %w[roles organization_structures organization_goals].each do |taxonomy_key|
      terms = Taxonomy.find_by!(key: taxonomy_key).taxonomy_terms.order(:position)

      expect(terms.last.key).to eq("other"), "expected Other last in #{taxonomy_key}"
      expect(terms.last.is_other).to be(true)
    end
  end

  it "retires a term that is no longer defined" do
    roles = Taxonomy.find_by!(key: "roles")
    stale = roles.taxonomy_terms.create!(key: "retired_role", label: "Retired role", position: 99)

    described_class.call

    expect(TaxonomyTerm.exists?(stale.id)).to be(false)
  end

  it "reassigns a key between terms without violating uniqueness" do
    roles = Taxonomy.find_by!(key: "roles")
    software_engineer = roles.taxonomy_terms.find_by!(key: "software_engineer")
    data_analyst = roles.taxonomy_terms.find_by!(key: "data_analyst")

    # Swap the two keys behind the seeder's back, then let it reconcile.
    software_engineer.update_columns(key: "temporarily_parked")
    data_analyst.update_columns(key: "software_engineer")
    software_engineer.update_columns(key: "data_analyst")

    expect { described_class.call }.not_to raise_error

    expect(software_engineer.reload.key).to eq("software_engineer")
    expect(data_analyst.reload.key).to eq("data_analyst")
  end

  it "refuses to retire a term that a profile still references" do
    roles = Taxonomy.find_by!(key: "roles")
    stale = roles.taxonomy_terms.create!(key: "retired_role", label: "Retired role", position: 99)
    user = create_user(email: "holder@example.com")
    user.create_profile!(minimum_profile_attributes(current_role_term: stale))

    expect { described_class.call }.to raise_error(/still referenced/)
  end
end
