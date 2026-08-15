# frozen_string_literal: true

class AddNotificationsAndEmail < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :timezone, :string, null: false, default: "UTC"

    create_table :notifications, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.uuid :recipient_user_id
      t.string :recipient_email, null: false
      t.string :event_key, null: false
      t.string :tier, null: false
      t.string :source_type, null: false
      t.uuid :source_id, null: false
      t.uuid :project_id
      t.uuid :organization_id
      t.uuid :actor_id
      t.jsonb :payload, null: false, default: {}
      t.datetime :read_at
      t.string :email_status, null: false, default: "pending"
      t.string :email_skip_reason
      t.string :coalesce_key
      t.datetime :sent_at
      t.timestamps
    end

    add_index :notifications, :recipient_user_id
    add_index :notifications, :email_status
    add_index :notifications, :coalesce_key
    add_index :notifications, :created_at
    add_index :notifications,
              [ :recipient_user_id, :event_key, :source_type, :source_id ],
              unique: true,
              where: "recipient_user_id IS NOT NULL",
              name: "index_notifications_user_idempotency"
    add_index :notifications,
              [ :recipient_email, :event_key, :source_type, :source_id ],
              unique: true,
              where: "recipient_user_id IS NULL",
              name: "index_notifications_email_idempotency"

    add_foreign_key :notifications, :users, column: :recipient_user_id
    add_foreign_key :notifications, :users, column: :actor_id
    add_foreign_key :notifications, :projects
    add_foreign_key :notifications, :organizations

    create_table :notification_preferences, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.uuid :user_id, null: false
      t.string :category, null: false
      t.boolean :email_enabled, null: false, default: true
      t.string :digest_cadence
      t.timestamps
    end

    add_index :notification_preferences, [ :user_id, :category ], unique: true
    add_foreign_key :notification_preferences, :users

    create_table :email_suppressions, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.string :address, null: false
      t.string :reason, null: false
      t.datetime :occurred_at, null: false
      t.timestamps
    end

    add_index :email_suppressions, :address, unique: true
  end
end
