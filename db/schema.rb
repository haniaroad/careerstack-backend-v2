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

ActiveRecord::Schema[8.0].define(version: 2026_08_11_200000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"
  enable_extension "pgcrypto"

  create_table "active_storage_attachments", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "name", null: false
    t.string "record_type", null: false
    t.uuid "record_id", null: false
    t.uuid "blob_id", null: false
    t.datetime "created_at", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "key", null: false
    t.string "filename", null: false
    t.string "content_type"
    t.text "metadata"
    t.string "service_name", null: false
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.datetime "created_at", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "age_visibility_preferences", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "user_id", null: false
    t.boolean "visibility_review_required", default: false, null: false
    t.boolean "public_identity_confirmed", default: false, null: false
    t.datetime "confirmed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_age_visibility_preferences_on_user_id", unique: true
  end

  create_table "ai_extraction_caches", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "blob_digest", null: false
    t.string "content_type"
    t.text "extracted_text"
    t.string "status", default: "succeeded", null: false
    t.string "error_code"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["blob_digest"], name: "index_ai_extraction_caches_on_blob_digest", unique: true
  end

  create_table "ai_generations", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "user_id", null: false
    t.uuid "workspace_id", null: false
    t.uuid "project_id"
    t.string "use_case", null: false
    t.string "status", default: "pending", null: false
    t.string "client_draft_key"
    t.text "prompt", null: false
    t.string "prompt_digest", null: false
    t.jsonb "constraints", default: {}, null: false
    t.jsonb "result", default: {}, null: false
    t.string "model"
    t.string "prompt_version"
    t.integer "prompt_tokens"
    t.integer "completion_tokens"
    t.integer "total_tokens"
    t.string "error_code"
    t.string "error_message"
    t.boolean "retryable", default: false, null: false
    t.datetime "started_at"
    t.datetime "succeeded_at"
    t.datetime "failed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["client_draft_key"], name: "index_ai_generations_on_client_draft_key"
    t.index ["project_id"], name: "index_ai_generations_on_project_id"
    t.index ["user_id", "status"], name: "index_ai_generations_on_user_id_and_status"
    t.index ["user_id", "succeeded_at"], name: "index_ai_generations_on_user_id_and_succeeded_at"
    t.index ["user_id"], name: "index_ai_generations_on_user_id"
    t.index ["workspace_id"], name: "index_ai_generations_on_workspace_id"
  end

  create_table "ai_review_reports", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "ai_review_id", null: false
    t.uuid "reporter_id", null: false
    t.string "report_type", null: false
    t.string "reason_category", null: false
    t.text "details"
    t.string "status", default: "open", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["ai_review_id"], name: "index_ai_review_reports_on_ai_review_id"
    t.index ["reporter_id"], name: "index_ai_review_reports_on_reporter_id"
  end

  create_table "ai_reviews", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "task_id", null: false
    t.uuid "task_submission_id", null: false
    t.uuid "user_id", null: false
    t.string "status", default: "pending", null: false
    t.string "decision"
    t.jsonb "feedback", default: {}, null: false
    t.boolean "analysis_incomplete", default: false, null: false
    t.jsonb "unsupported_items", default: [], null: false
    t.string "model"
    t.string "prompt_version"
    t.integer "prompt_tokens"
    t.integer "completion_tokens"
    t.integer "total_tokens"
    t.string "error_code"
    t.text "error_message"
    t.integer "technical_retry_count", default: 0, null: false
    t.boolean "counts_as_attempt", default: false, null: false
    t.string "content_fingerprint", null: false
    t.datetime "started_at"
    t.datetime "completed_at"
    t.integer "processing_ms"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["status"], name: "index_ai_reviews_on_status"
    t.index ["task_id", "status"], name: "index_ai_reviews_on_task_id_and_status"
    t.index ["task_id"], name: "index_ai_reviews_on_task_id"
    t.index ["task_id"], name: "index_ai_reviews_one_active_per_task", unique: true, where: "((status)::text = ANY ((ARRAY['pending'::character varying, 'running'::character varying])::text[]))"
    t.index ["task_submission_id"], name: "index_ai_reviews_on_task_submission_id"
    t.index ["user_id", "created_at"], name: "index_ai_reviews_on_user_id_and_created_at"
    t.index ["user_id"], name: "index_ai_reviews_on_user_id"
  end

  create_table "contribution_events", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "user_id", null: false
    t.string "kind", null: false
    t.datetime "occurred_at", null: false
    t.string "subject_type", null: false
    t.uuid "subject_id", null: false
    t.string "workspace_kind", null: false
    t.boolean "private_org", default: false, null: false
    t.string "idempotency_key", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["idempotency_key"], name: "index_contribution_events_on_idempotency_key", unique: true
    t.index ["kind"], name: "index_contribution_events_on_kind"
    t.index ["subject_type", "subject_id"], name: "index_contribution_events_on_subject_type_and_subject_id"
    t.index ["user_id", "occurred_at"], name: "index_contribution_events_on_user_id_and_occurred_at"
    t.index ["user_id"], name: "index_contribution_events_on_user_id"
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
    t.string "related_type"
    t.uuid "related_id"
    t.uuid "credit_lot_id"
    t.index ["actor_user_id"], name: "index_credit_ledger_entries_on_actor_user_id"
    t.index ["idempotency_key"], name: "index_credit_ledger_entries_on_idempotency_key", unique: true
    t.index ["owner_type", "owner_id"], name: "index_credit_ledger_entries_on_owner_type_and_owner_id"
    t.index ["related_type", "related_id"], name: "index_credit_ledger_entries_on_related_type_and_related_id"
  end

  create_table "credit_lots", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "owner_type", null: false
    t.uuid "owner_id", null: false
    t.string "source", null: false
    t.integer "original_amount", null: false
    t.integer "remaining", null: false
    t.string "stripe_payment_ref"
    t.datetime "granted_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["owner_type", "owner_id", "granted_at"], name: "index_credit_lots_on_owner_type_and_owner_id_and_granted_at"
    t.index ["stripe_payment_ref"], name: "index_credit_lots_on_stripe_payment_ref", unique: true, where: "(stripe_payment_ref IS NOT NULL)"
  end

  create_table "credit_purchases", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "user_id", null: false
    t.uuid "credit_lot_id"
    t.string "stripe_checkout_session_id", null: false
    t.string "stripe_payment_intent_id"
    t.string "status", default: "pending", null: false
    t.integer "credits", default: 3, null: false
    t.integer "amount_cents", default: 2000, null: false
    t.string "currency", default: "usd", null: false
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["credit_lot_id"], name: "index_credit_purchases_on_credit_lot_id"
    t.index ["status"], name: "index_credit_purchases_on_status"
    t.index ["stripe_checkout_session_id"], name: "index_credit_purchases_on_stripe_checkout_session_id", unique: true
    t.index ["user_id"], name: "index_credit_purchases_on_user_id"
  end

  create_table "credit_refund_requests", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "user_id", null: false
    t.uuid "credit_purchase_id", null: false
    t.string "status", default: "submitted", null: false
    t.text "reason"
    t.integer "unused_credits_at_request", null: false
    t.datetime "resolved_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["credit_purchase_id"], name: "index_credit_refund_requests_on_credit_purchase_id"
    t.index ["status"], name: "index_credit_refund_requests_on_status"
    t.index ["user_id"], name: "index_credit_refund_requests_on_user_id"
  end

  create_table "escalations", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "workspace_id", null: false
    t.uuid "project_id", null: false
    t.string "target", null: false
    t.uuid "organization_id"
    t.string "reason", null: false
    t.string "subject_type", null: false
    t.uuid "subject_id", null: false
    t.string "status", default: "open", null: false
    t.string "idempotency_key", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["idempotency_key"], name: "index_escalations_on_idempotency_key", unique: true
    t.index ["organization_id"], name: "index_escalations_on_organization_id"
    t.index ["project_id"], name: "index_escalations_on_project_id"
    t.index ["status"], name: "index_escalations_on_status"
    t.index ["subject_type", "subject_id"], name: "index_escalations_on_subject_type_and_subject_id"
    t.index ["workspace_id"], name: "index_escalations_on_workspace_id"
  end

  create_table "inbox_alerts", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "workspace_id", null: false
    t.uuid "recipient_user_id"
    t.uuid "organization_id"
    t.string "audience", default: "user", null: false
    t.string "kind", null: false
    t.string "subject_type", null: false
    t.uuid "subject_id", null: false
    t.uuid "project_id"
    t.string "title", null: false
    t.text "body", null: false
    t.string "urgency", default: "medium", null: false
    t.boolean "overdue", default: false, null: false
    t.string "idempotency_key", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["idempotency_key"], name: "index_inbox_alerts_on_idempotency_key", unique: true
    t.index ["organization_id"], name: "index_inbox_alerts_on_organization_id"
    t.index ["project_id"], name: "index_inbox_alerts_on_project_id"
    t.index ["recipient_user_id"], name: "index_inbox_alerts_on_recipient_user_id"
    t.index ["subject_type", "subject_id"], name: "index_inbox_alerts_on_subject_type_and_subject_id"
    t.index ["workspace_id"], name: "index_inbox_alerts_on_workspace_id"
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
    t.string "slug", null: false
    t.index ["current_role_term_id"], name: "index_profiles_on_current_role_term_id"
    t.index ["slug"], name: "index_profiles_on_slug", unique: true
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

  create_table "project_applications", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "project_id", null: false
    t.uuid "applicant_id", null: false
    t.string "requested_role", null: false
    t.text "motivation", null: false
    t.boolean "availability_confirmed", default: false, null: false
    t.jsonb "skills", default: [], null: false
    t.string "portfolio_url"
    t.string "github_url"
    t.string "resume_url"
    t.string "status", default: "pending", null: false
    t.text "rejection_reason"
    t.uuid "reviewed_by_id"
    t.datetime "reviewed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "overdue_at"
    t.index ["applicant_id"], name: "index_project_applications_on_applicant_id"
    t.index ["overdue_at"], name: "index_project_applications_on_overdue_at"
    t.index ["project_id", "applicant_id", "status"], name: "idx_on_project_id_applicant_id_status_438a336b2c"
    t.index ["project_id"], name: "index_project_applications_on_project_id"
    t.index ["status", "created_at"], name: "index_project_applications_on_status_and_created_at"
  end

  create_table "project_invitations", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "project_id", null: false
    t.uuid "inviter_id", null: false
    t.uuid "invitee_id", null: false
    t.string "requested_role", null: false
    t.string "status", default: "pending", null: false
    t.datetime "responded_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["invitee_id"], name: "index_project_invitations_on_invitee_id"
    t.index ["project_id", "invitee_id", "status"], name: "idx_on_project_id_invitee_id_status_9fcc4028a3"
    t.index ["project_id"], name: "index_project_invitations_on_project_id"
  end

  create_table "project_membership_events", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "project_membership_id", null: false
    t.uuid "project_id", null: false
    t.uuid "user_id", null: false
    t.uuid "actor_user_id"
    t.string "event_type", null: false
    t.string "reason_category"
    t.text "reason_detail"
    t.string "join_source"
    t.string "participant_role"
    t.datetime "created_at", null: false
    t.index ["project_id"], name: "index_project_membership_events_on_project_id"
    t.index ["project_membership_id"], name: "index_project_membership_events_on_project_membership_id"
    t.index ["user_id"], name: "index_project_membership_events_on_user_id"
  end

  create_table "project_memberships", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "project_id", null: false
    t.uuid "user_id", null: false
    t.string "role", default: "creator", null: false
    t.string "status", default: "active", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "participant_role"
    t.string "join_source"
    t.index ["project_id", "user_id"], name: "index_project_memberships_on_project_id_and_user_id", unique: true
    t.index ["project_id"], name: "index_project_memberships_on_project_id"
    t.index ["user_id", "status"], name: "index_project_memberships_on_user_id_and_status"
    t.index ["user_id"], name: "index_project_memberships_on_user_id"
  end

  create_table "projects", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "workspace_id", null: false
    t.uuid "creator_id", null: false
    t.string "title", null: false
    t.text "summary"
    t.jsonb "skills", default: [], null: false
    t.string "mode", default: "solo", null: false
    t.string "status", default: "draft", null: false
    t.datetime "confirmed_at"
    t.datetime "cancelled_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.text "objective"
    t.string "project_type"
    t.string "expected_duration"
    t.date "ends_on"
    t.text "definition_of_done"
    t.jsonb "roles_needed", default: [], null: false
    t.jsonb "proposed_tasks", default: [], null: false
    t.text "submission_expectations"
    t.string "source", default: "manual", null: false
    t.datetime "ai_generation_succeeded_at"
    t.string "joining_mode"
    t.integer "capacity"
    t.datetime "completed_at"
    t.datetime "expired_at"
    t.index ["creator_id", "status"], name: "index_projects_on_creator_id_and_status"
    t.index ["creator_id"], name: "index_projects_on_creator_id"
    t.index ["workspace_id", "status"], name: "index_projects_on_workspace_id_and_status"
    t.index ["workspace_id"], name: "index_projects_on_workspace_id"
  end

  create_table "stripe_customers", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "user_id", null: false
    t.string "stripe_customer_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["stripe_customer_id"], name: "index_stripe_customers_on_stripe_customer_id", unique: true
    t.index ["user_id"], name: "index_stripe_customers_on_user_id", unique: true
  end

  create_table "stripe_webhook_events", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "stripe_event_id", null: false
    t.string "event_type", null: false
    t.string "processing_status", default: "processed", null: false
    t.text "error_message"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["stripe_event_id"], name: "index_stripe_webhook_events_on_stripe_event_id", unique: true
  end

  create_table "task_submission_links", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "task_submission_id", null: false
    t.string "url", limit: 2048, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["task_submission_id"], name: "index_task_submission_links_on_task_submission_id"
  end

  create_table "task_submissions", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "task_id", null: false
    t.uuid "submitted_by_id", null: false
    t.integer "attempt_number", null: false
    t.text "body"
    t.string "content_fingerprint", null: false
    t.datetime "submitted_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["submitted_by_id"], name: "index_task_submissions_on_submitted_by_id"
    t.index ["task_id", "attempt_number"], name: "index_task_submissions_on_task_id_and_attempt_number", unique: true
    t.index ["task_id"], name: "index_task_submissions_on_task_id"
  end

  create_table "tasks", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "project_id", null: false
    t.uuid "assignee_id"
    t.string "title", limit: 200, null: false
    t.text "acceptance_criteria"
    t.text "submission_expectations"
    t.date "due_on"
    t.string "status", default: "pending", null: false
    t.integer "position", default: 0, null: false
    t.datetime "first_submitted_at"
    t.boolean "on_time"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "creator_review_decision"
    t.text "creator_review_feedback"
    t.uuid "creator_reviewed_by_id"
    t.datetime "creator_reviewed_at"
    t.datetime "review_overdue_at"
    t.index ["assignee_id", "status"], name: "index_tasks_on_assignee_id_and_status"
    t.index ["assignee_id"], name: "index_tasks_on_assignee_id"
    t.index ["creator_reviewed_by_id"], name: "index_tasks_on_creator_reviewed_by_id"
    t.index ["project_id", "status"], name: "index_tasks_on_project_id_and_status"
    t.index ["project_id"], name: "index_tasks_on_project_id"
    t.index ["review_overdue_at"], name: "index_tasks_on_review_overdue_at"
    t.index ["status", "first_submitted_at"], name: "index_tasks_on_status_and_first_submitted_at"
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

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "age_visibility_preferences", "users"
  add_foreign_key "ai_generations", "projects"
  add_foreign_key "ai_generations", "users"
  add_foreign_key "ai_generations", "workspaces"
  add_foreign_key "ai_review_reports", "ai_reviews"
  add_foreign_key "ai_review_reports", "users", column: "reporter_id"
  add_foreign_key "ai_reviews", "task_submissions"
  add_foreign_key "ai_reviews", "tasks"
  add_foreign_key "ai_reviews", "users"
  add_foreign_key "contribution_events", "users"
  add_foreign_key "credit_ledger_entries", "credit_lots"
  add_foreign_key "credit_ledger_entries", "users", column: "actor_user_id"
  add_foreign_key "credit_purchases", "credit_lots"
  add_foreign_key "credit_purchases", "users"
  add_foreign_key "credit_refund_requests", "credit_purchases"
  add_foreign_key "credit_refund_requests", "users"
  add_foreign_key "escalations", "organizations"
  add_foreign_key "escalations", "projects"
  add_foreign_key "escalations", "workspaces"
  add_foreign_key "inbox_alerts", "organizations"
  add_foreign_key "inbox_alerts", "projects"
  add_foreign_key "inbox_alerts", "users", column: "recipient_user_id"
  add_foreign_key "inbox_alerts", "workspaces"
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
  add_foreign_key "project_applications", "projects"
  add_foreign_key "project_applications", "users", column: "applicant_id"
  add_foreign_key "project_applications", "users", column: "reviewed_by_id"
  add_foreign_key "project_invitations", "projects"
  add_foreign_key "project_invitations", "users", column: "invitee_id"
  add_foreign_key "project_invitations", "users", column: "inviter_id"
  add_foreign_key "project_membership_events", "project_memberships"
  add_foreign_key "project_membership_events", "projects"
  add_foreign_key "project_membership_events", "users"
  add_foreign_key "project_membership_events", "users", column: "actor_user_id"
  add_foreign_key "project_memberships", "projects"
  add_foreign_key "project_memberships", "users"
  add_foreign_key "projects", "users", column: "creator_id"
  add_foreign_key "projects", "workspaces"
  add_foreign_key "stripe_customers", "users"
  add_foreign_key "task_submission_links", "task_submissions"
  add_foreign_key "task_submissions", "tasks"
  add_foreign_key "task_submissions", "users", column: "submitted_by_id"
  add_foreign_key "tasks", "projects"
  add_foreign_key "tasks", "users", column: "assignee_id"
  add_foreign_key "tasks", "users", column: "creator_reviewed_by_id"
  add_foreign_key "taxonomy_terms", "taxonomies"
  add_foreign_key "users", "workspaces", column: "active_workspace_id"
  add_foreign_key "users", "workspaces", column: "personal_workspace_id"
  add_foreign_key "workspaces", "organizations"
  add_foreign_key "workspaces", "users", column: "owner_user_id"
end
