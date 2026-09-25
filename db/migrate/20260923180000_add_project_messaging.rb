# frozen_string_literal: true

class AddProjectMessaging < ActiveRecord::Migration[8.0]
  def change
    create_table :project_messages, id: :uuid do |t|
      t.references :project, null: false, foreign_key: true, type: :uuid
      t.references :author, null: false, foreign_key: { to_table: :users }, type: :uuid
      t.text :body, null: false
      t.timestamps
    end
    add_index :project_messages, [ :project_id, :created_at ]

    add_column :project_memberships, :messages_last_read_at, :datetime

    create_table :project_message_reports, id: :uuid do |t|
      t.references :project_message, null: false, foreign_key: true, type: :uuid
      t.references :reporter, null: false, foreign_key: { to_table: :users }, type: :uuid
      t.string :report_type, null: false
      t.string :reason_category, null: false
      t.text :details
      t.string :status, null: false, default: "open"
      t.timestamps
    end
    add_index :project_message_reports,
              [ :project_message_id, :reporter_id ],
              unique: true,
              where: "status = 'open'",
              name: "index_project_message_reports_open_per_reporter"
  end
end
