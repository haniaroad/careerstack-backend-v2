# frozen_string_literal: true

class CreateTasksAndSubmissions < ActiveRecord::Migration[8.0]
  def change
    create_table :tasks, id: :uuid do |t|
      t.references :project, null: false, foreign_key: true, type: :uuid
      t.references :assignee, null: false, foreign_key: { to_table: :users }, type: :uuid
      t.string :title, null: false, limit: 200
      t.text :acceptance_criteria
      t.text :submission_expectations
      t.date :due_on
      t.string :status, null: false, default: "pending"
      t.integer :position, null: false, default: 0
      t.datetime :first_submitted_at
      t.boolean :on_time
      t.timestamps
    end

    add_index :tasks, [ :project_id, :status ]
    add_index :tasks, [ :assignee_id, :status ]

    create_table :task_submissions, id: :uuid do |t|
      t.references :task, null: false, foreign_key: true, type: :uuid
      t.references :submitted_by, null: false, foreign_key: { to_table: :users }, type: :uuid
      t.integer :attempt_number, null: false
      t.text :body
      t.string :content_fingerprint, null: false
      t.datetime :submitted_at, null: false
      t.timestamps
    end

    add_index :task_submissions, [ :task_id, :attempt_number ], unique: true

    create_table :task_submission_links, id: :uuid do |t|
      t.references :task_submission, null: false, foreign_key: true, type: :uuid
      t.string :url, null: false, limit: 2048
      t.timestamps
    end
  end
end
