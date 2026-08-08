# frozen_string_literal: true

class CreateAiReviewsAndReports < ActiveRecord::Migration[8.0]
  def change
    create_table :ai_reviews, id: :uuid do |t|
      t.references :task, null: false, foreign_key: true, type: :uuid
      t.references :task_submission, null: false, foreign_key: true, type: :uuid
      t.references :user, null: false, foreign_key: true, type: :uuid
      t.string :status, null: false, default: "pending"
      t.string :decision
      t.jsonb :feedback, null: false, default: {}
      t.boolean :analysis_incomplete, null: false, default: false
      t.jsonb :unsupported_items, null: false, default: []
      t.string :model
      t.string :prompt_version
      t.integer :prompt_tokens
      t.integer :completion_tokens
      t.integer :total_tokens
      t.string :error_code
      t.text :error_message
      t.integer :technical_retry_count, null: false, default: 0
      t.boolean :counts_as_attempt, null: false, default: false
      t.string :content_fingerprint, null: false
      t.datetime :started_at
      t.datetime :completed_at
      t.integer :processing_ms
      t.timestamps
    end

    add_index :ai_reviews, :status
    add_index :ai_reviews, [ :task_id, :status ]
    add_index :ai_reviews, [ :user_id, :created_at ]
    add_index :ai_reviews, [ :task_id ],
              unique: true,
              where: "status IN ('pending', 'running')",
              name: "index_ai_reviews_one_active_per_task"

    create_table :ai_review_reports, id: :uuid do |t|
      t.references :ai_review, null: false, foreign_key: true, type: :uuid
      t.references :reporter, null: false, foreign_key: { to_table: :users }, type: :uuid
      t.string :report_type, null: false
      t.string :reason_category, null: false
      t.text :details
      t.string :status, null: false, default: "open"
      t.timestamps
    end

    create_table :ai_extraction_caches, id: :uuid do |t|
      t.string :blob_digest, null: false
      t.string :content_type
      t.text :extracted_text
      t.string :status, null: false, default: "succeeded"
      t.string :error_code
      t.timestamps
    end

    add_index :ai_extraction_caches, :blob_digest, unique: true
  end
end
