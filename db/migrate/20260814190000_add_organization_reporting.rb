# frozen_string_literal: true

class AddOrganizationReporting < ActiveRecord::Migration[8.0]
  def up
    create_table :organization_reports, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :organization, type: :uuid, null: false, foreign_key: true
      t.references :program, type: :uuid, foreign_key: true
      t.references :requested_by, type: :uuid, null: false, foreign_key: { to_table: :users }
      t.date :period_starts_on, null: false
      t.date :period_ends_on, null: false
      t.string :format, null: false
      t.boolean :aggregate_only, null: false, default: false
      t.string :status, null: false, default: "draft"
      t.boolean :includes_minor_names, null: false, default: false
      t.datetime :generated_at
      t.string :error_code
      t.jsonb :metrics_json, null: false, default: {}
      t.text :methodology_note
      t.timestamps
    end
    add_index :organization_reports, [ :organization_id, :status ]

    create_table :organization_report_audits, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :organization, type: :uuid, null: false, foreign_key: true
      t.references :organization_report, type: :uuid, null: false, foreign_key: true
      t.references :actor, type: :uuid, null: false, foreign_key: { to_table: :users }
      t.string :action, null: false
      t.string :format, null: false
      t.boolean :aggregate_only, null: false, default: false
      t.boolean :includes_minor_names, null: false, default: false
      t.datetime :occurred_at, null: false
      t.timestamps
    end
    add_index :organization_report_audits, [ :organization_id, :occurred_at ]

    create_table :self_reported_outcomes, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :user, type: :uuid, null: false, foreign_key: true
      t.references :organization, type: :uuid, null: false, foreign_key: true
      t.references :program, type: :uuid, foreign_key: true
      t.references :project, type: :uuid, foreign_key: true
      t.string :outcome_type, null: false
      t.date :occurred_on, null: false
      t.string :careerstack_contribution, null: false
      t.string :institution
      t.string :title
      t.text :note
      t.string :reporting_label, null: false, default: "self_reported"
      t.timestamps
    end
    add_index :self_reported_outcomes, [ :organization_id, :outcome_type ]
    add_index :self_reported_outcomes, [ :user_id, :occurred_on ]
  end

  def down
    drop_table :self_reported_outcomes
    drop_table :organization_report_audits
    drop_table :organization_reports
  end
end
