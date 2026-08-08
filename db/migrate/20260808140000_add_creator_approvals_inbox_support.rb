# frozen_string_literal: true

class AddCreatorApprovalsInboxSupport < ActiveRecord::Migration[8.0]
  def change
    change_table :tasks, bulk: true do |t|
      t.string :creator_review_decision
      t.text :creator_review_feedback
      t.uuid :creator_reviewed_by_id
      t.datetime :creator_reviewed_at
      t.datetime :review_overdue_at
    end

    add_index :tasks, :creator_reviewed_by_id
    add_index :tasks, [ :status, :first_submitted_at ], name: "index_tasks_on_status_and_first_submitted_at"
    add_index :tasks, :review_overdue_at

    add_column :project_applications, :overdue_at, :datetime
    add_index :project_applications, [ :status, :created_at ], name: "index_project_applications_on_status_and_created_at"
    add_index :project_applications, :overdue_at

    create_table :inbox_alerts, id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
      t.uuid :workspace_id, null: false
      t.uuid :recipient_user_id
      t.uuid :organization_id
      t.string :audience, null: false, default: "user"
      t.string :kind, null: false
      t.string :subject_type, null: false
      t.uuid :subject_id, null: false
      t.uuid :project_id
      t.string :title, null: false
      t.text :body, null: false
      t.string :urgency, null: false, default: "medium"
      t.boolean :overdue, null: false, default: false
      t.string :idempotency_key, null: false
      t.datetime :created_at, null: false
      t.datetime :updated_at, null: false

      t.index :workspace_id
      t.index :recipient_user_id
      t.index :organization_id
      t.index :idempotency_key, unique: true
      t.index [ :subject_type, :subject_id ]
      t.index :project_id
    end

    create_table :escalations, id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
      t.uuid :workspace_id, null: false
      t.uuid :project_id, null: false
      t.string :target, null: false
      t.uuid :organization_id
      t.string :reason, null: false
      t.string :subject_type, null: false
      t.uuid :subject_id, null: false
      t.string :status, null: false, default: "open"
      t.string :idempotency_key, null: false
      t.datetime :created_at, null: false
      t.datetime :updated_at, null: false

      t.index :workspace_id
      t.index :project_id
      t.index :organization_id
      t.index :idempotency_key, unique: true
      t.index [ :subject_type, :subject_id ]
      t.index :status
    end

    add_foreign_key :tasks, :users, column: :creator_reviewed_by_id
    add_foreign_key :inbox_alerts, :workspaces
    add_foreign_key :inbox_alerts, :users, column: :recipient_user_id
    add_foreign_key :inbox_alerts, :organizations
    add_foreign_key :inbox_alerts, :projects
    add_foreign_key :escalations, :workspaces
    add_foreign_key :escalations, :projects
    add_foreign_key :escalations, :organizations
  end
end
