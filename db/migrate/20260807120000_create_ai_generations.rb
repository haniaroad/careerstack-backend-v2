# frozen_string_literal: true

class CreateAiGenerations < ActiveRecord::Migration[8.0]
  def change
    create_table :ai_generations, id: :uuid do |t|
      t.references :user, null: false, foreign_key: true, type: :uuid
      t.references :workspace, null: false, foreign_key: true, type: :uuid
      t.references :project, null: true, foreign_key: true, type: :uuid
      t.string :use_case, null: false
      t.string :status, null: false, default: "pending"
      t.string :client_draft_key
      t.text :prompt, null: false
      t.string :prompt_digest, null: false
      t.jsonb :constraints, null: false, default: {}
      t.jsonb :result, null: false, default: {}
      t.string :model
      t.string :prompt_version
      t.integer :prompt_tokens
      t.integer :completion_tokens
      t.integer :total_tokens
      t.string :error_code
      t.string :error_message
      t.boolean :retryable, null: false, default: false
      t.datetime :started_at
      t.datetime :succeeded_at
      t.datetime :failed_at
      t.timestamps
    end

    add_index :ai_generations, [ :user_id, :status ]
    add_index :ai_generations, [ :user_id, :succeeded_at ]
    add_index :ai_generations, [ :client_draft_key ]
  end
end
