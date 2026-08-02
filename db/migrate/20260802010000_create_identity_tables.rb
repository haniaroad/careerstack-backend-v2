# frozen_string_literal: true

class CreateIdentityTables < ActiveRecord::Migration[8.0]
  def change
    enable_extension "pgcrypto" unless extension_enabled?("pgcrypto")

    create_table :taxonomies, id: :uuid do |t|
      t.string :key, null: false
      t.string :name, null: false
      t.timestamps
    end
    add_index :taxonomies, :key, unique: true

    create_table :taxonomy_terms, id: :uuid do |t|
      t.references :taxonomy, type: :uuid, null: false, foreign_key: true
      t.string :key, null: false
      t.string :label, null: false
      t.integer :position, null: false, default: 0
      t.boolean :is_other, null: false, default: false
      t.timestamps
    end
    add_index :taxonomy_terms, [ :taxonomy_id, :key ], unique: true

    create_table :users, id: :uuid do |t|
      t.string :firebase_uid, null: false
      t.string :email, null: false
      t.string :status, null: false, default: "pending_onboarding"
      t.string :age_status
      t.string :onboarding_path
      t.datetime :terms_accepted_at
      t.datetime :age_attested_at
      t.uuid :personal_workspace_id
      t.uuid :active_workspace_id
      t.boolean :personal_trial_granted, null: false, default: false
      t.boolean :organization_trial_granted, null: false, default: false
      t.timestamps
    end
    add_index :users, :firebase_uid, unique: true
    add_index :users, :email, unique: true

    create_table :organizations, id: :uuid do |t|
      t.string :name, null: false
      t.references :structure_term, type: :uuid, foreign_key: { to_table: :taxonomy_terms }
      t.string :structure_other
      t.string :country, null: false
      t.string :state_region, null: false
      t.references :primary_goal_term, type: :uuid, foreign_key: { to_table: :taxonomy_terms }
      t.string :primary_goal_other
      t.string :website
      t.string :logo_url
      t.string :expected_participant_range
      t.string :timezone, null: false, default: "UTC"
      t.timestamps
    end

    create_table :workspaces, id: :uuid do |t|
      t.string :kind, null: false
      t.string :name, null: false
      t.references :owner_user, type: :uuid, foreign_key: { to_table: :users }, index: false
      t.references :organization, type: :uuid, foreign_key: true, index: false
      t.timestamps
    end
    add_index :workspaces, :owner_user_id, unique: true, where: "kind = 'personal'", name: "index_workspaces_personal_owner"
    add_index :workspaces, :organization_id, unique: true, where: "kind = 'organization'", name: "index_workspaces_org_unique"

    add_foreign_key :users, :workspaces, column: :personal_workspace_id
    add_foreign_key :users, :workspaces, column: :active_workspace_id

    create_table :programs, id: :uuid do |t|
      t.references :organization, type: :uuid, null: false, foreign_key: true
      t.string :name, null: false
      t.timestamps
    end

    create_table :organization_memberships, id: :uuid do |t|
      t.references :organization, type: :uuid, null: false, foreign_key: true
      t.references :user, type: :uuid, null: false, foreign_key: true
      t.string :role, null: false, default: "participant"
      t.references :program, type: :uuid, foreign_key: true
      t.references :program_filter_program, type: :uuid, foreign_key: { to_table: :programs }
      t.timestamps
    end
    add_index :organization_memberships, [ :organization_id, :user_id ], unique: true

    create_table :profiles, id: :uuid do |t|
      t.references :user, type: :uuid, null: false, foreign_key: true, index: { unique: true }
      t.string :display_name, null: false
      t.string :country, null: false
      t.string :state_region, null: false
      t.string :career_goal, null: false
      t.references :current_role_term, type: :uuid, foreign_key: { to_table: :taxonomy_terms }
      t.string :current_role_other
      t.string :experience_level, null: false
      t.references :target_role_term, type: :uuid, foreign_key: { to_table: :taxonomy_terms }
      t.string :target_role_other
      t.text :bio
      t.string :image_url
      t.string :github_url
      t.string :linkedin_url
      t.string :portfolio_url
      t.jsonb :interests, null: false, default: []
      t.date :date_of_birth
      t.timestamps
    end

    create_table :invitations, id: :uuid do |t|
      t.references :organization, type: :uuid, null: false, foreign_key: true
      t.references :program, type: :uuid, foreign_key: true
      t.string :email
      t.string :token_digest, null: false
      t.datetime :expires_at, null: false
      t.datetime :accepted_at
      t.references :accepted_by_user, type: :uuid, foreign_key: { to_table: :users }
      t.references :created_by_user, type: :uuid, foreign_key: { to_table: :users }
      t.string :role, null: false, default: "participant"
      t.timestamps
    end
    add_index :invitations, :token_digest, unique: true

    create_table :credit_ledger_entries, id: :uuid do |t|
      t.string :owner_type, null: false
      t.uuid :owner_id, null: false
      t.string :event, null: false
      t.integer :amount, null: false
      t.references :actor_user, type: :uuid, foreign_key: { to_table: :users }
      t.string :reason, null: false
      t.string :idempotency_key, null: false
      t.timestamps
    end
    add_index :credit_ledger_entries, :idempotency_key, unique: true
    add_index :credit_ledger_entries, [ :owner_type, :owner_id ]

    create_table :age_visibility_preferences, id: :uuid do |t|
      t.references :user, type: :uuid, null: false, foreign_key: true, index: { unique: true }
      t.boolean :visibility_review_required, null: false, default: false
      t.boolean :public_identity_confirmed, null: false, default: false
      t.datetime :confirmed_at
      t.timestamps
    end
  end
end
