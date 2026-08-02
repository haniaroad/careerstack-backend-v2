# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.0].define(version: 2026_08_02_010000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"
  enable_extension "pgcrypto"

  create_table "age_visibility_preferences", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "user_id", null: false
    t.boolean "visibility_review_required", default: false, null: false
    t.boolean "public_identity_confirmed", default: false, null: false
    t.datetime "confirmed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_age_visibility_preferences_on_user_id", unique: true
  end

  create_table "credit_ledger_entries", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "owner_type", null: false
    t.uuid "owner_id", null: false
    t.string "event", null: false
    t.integer "amount", null: false
    t.uuid "actor_user_id"
    t.string "reason", null: false
    t.string "idempotency_key", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["actor_user_id"], name: "index_credit_ledger_entries_on_actor_user_id"
    t.index ["idempotency_key"], name: "index_credit_ledger_entries_on_idempotency_key", unique: true
    t.index ["owner_type", "owner_id"], name: "index_credit_ledger_entries_on_owner_type_and_owner_id"
  end

  create_table "invitations", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "organization_id", null: false
    t.uuid "program_id"
    t.string "email"
    t.string "token_digest", null: false
    t.datetime "expires_at", null: false
    t.datetime "accepted_at"
    t.uuid "accepted_by_user_id"
    t.uuid "created_by_user_id"
    t.string "role", default: "participant", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["accepted_by_user_id"], name: "index_invitations_on_accepted_by_user_id"
    t.index ["created_by_user_id"], name: "index_invitations_on_created_by_user_id"
    t.index ["organization_id"], name: "index_invitations_on_organization_id"
    t.index ["program_id"], name: "index_invitations_on_program_id"
    t.index ["token_digest"], name: "index_invitations_on_token_digest", unique: true
  end

  create_table "organization_memberships", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "organization_id", null: false
    t.uuid "user_id", null: false
    t.string "role", default: "participant", null: false
    t.uuid "program_id"
    t.uuid "program_filter_program_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["organization_id", "user_id"], name: "index_organization_memberships_on_organization_id_and_user_id", unique: true
    t.index ["organization_id"], name: "index_organization_memberships_on_organization_id"
    t.index ["program_filter_program_id"], name: "index_organization_memberships_on_program_filter_program_id"
    t.index ["program_id"], name: "index_organization_memberships_on_program_id"
    t.index ["user_id"], name: "index_organization_memberships_on_user_id"
  end

  create_table "organizations", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "name", null: false
    t.uuid "structure_term_id"
    t.string "structure_other"
    t.string "country", null: false
    t.string "state_region", null: false
    t.uuid "primary_goal_term_id"
    t.string "primary_goal_other"
    t.string "website"
    t.string "logo_url"
    t.string "expected_participant_range"
    t.string "timezone", default: "UTC", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["primary_goal_term_id"], name: "index_organizations_on_primary_goal_term_id"
    t.index ["structure_term_id"], name: "index_organizations_on_structure_term_id"
  end

  create_table "profiles", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "user_id", null: false
    t.string "display_name", null: false
    t.string "country", null: false
    t.string "state_region", null: false
    t.string "career_goal", null: false
    t.uuid "current_role_term_id"
    t.string "current_role_other"
    t.string "experience_level", null: false
    t.uuid "target_role_term_id"
    t.string "target_role_other"
    t.text "bio"
    t.string "image_url"
    t.string "github_url"
    t.string "linkedin_url"
    t.string "portfolio_url"
    t.jsonb "interests", default: [], null: false
    t.date "date_of_birth"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["current_role_term_id"], name: "index_profiles_on_current_role_term_id"
    t.index ["target_role_term_id"], name: "index_profiles_on_target_role_term_id"
    t.index ["user_id"], name: "index_profiles_on_user_id", unique: true
  end

  create_table "programs", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "organization_id", null: false
    t.string "name", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["organization_id"], name: "index_programs_on_organization_id"
  end

  create_table "taxonomies", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "key", null: false
    t.string "name", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_taxonomies_on_key", unique: true
  end

  create_table "taxonomy_terms", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "taxonomy_id", null: false
    t.string "key", null: false
    t.string "label", null: false
    t.integer "position", default: 0, null: false
    t.boolean "is_other", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["taxonomy_id", "key"], name: "index_taxonomy_terms_on_taxonomy_id_and_key", unique: true
    t.index ["taxonomy_id"], name: "index_taxonomy_terms_on_taxonomy_id"
  end

  create_table "users", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "firebase_uid", null: false
    t.string "email", null: false
    t.string "status", default: "pending_onboarding", null: false
    t.string "age_status"
    t.string "onboarding_path"
    t.datetime "terms_accepted_at"
    t.datetime "age_attested_at"
    t.uuid "personal_workspace_id"
    t.uuid "active_workspace_id"
    t.boolean "personal_trial_granted", default: false, null: false
    t.boolean "organization_trial_granted", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["firebase_uid"], name: "index_users_on_firebase_uid", unique: true
  end

  create_table "workspaces", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "kind", null: false
    t.string "name", null: false
    t.uuid "owner_user_id"
    t.uuid "organization_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["organization_id"], name: "index_workspaces_org_unique", unique: true, where: "((kind)::text = 'organization'::text)"
    t.index ["owner_user_id"], name: "index_workspaces_personal_owner", unique: true, where: "((kind)::text = 'personal'::text)"
  end

  add_foreign_key "age_visibility_preferences", "users"
  add_foreign_key "credit_ledger_entries", "users", column: "actor_user_id"
  add_foreign_key "invitations", "organizations"
  add_foreign_key "invitations", "programs"
  add_foreign_key "invitations", "users", column: "accepted_by_user_id"
  add_foreign_key "invitations", "users", column: "created_by_user_id"
  add_foreign_key "organization_memberships", "organizations"
  add_foreign_key "organization_memberships", "programs"
  add_foreign_key "organization_memberships", "programs", column: "program_filter_program_id"
  add_foreign_key "organization_memberships", "users"
  add_foreign_key "organizations", "taxonomy_terms", column: "primary_goal_term_id"
  add_foreign_key "organizations", "taxonomy_terms", column: "structure_term_id"
  add_foreign_key "profiles", "taxonomy_terms", column: "current_role_term_id"
  add_foreign_key "profiles", "taxonomy_terms", column: "target_role_term_id"
  add_foreign_key "profiles", "users"
  add_foreign_key "programs", "organizations"
  add_foreign_key "taxonomy_terms", "taxonomies"
  add_foreign_key "users", "workspaces", column: "active_workspace_id"
  add_foreign_key "users", "workspaces", column: "personal_workspace_id"
  add_foreign_key "workspaces", "organizations"
  add_foreign_key "workspaces", "users", column: "owner_user_id"
end
