# frozen_string_literal: true

class AddPlatformAdmin < ActiveRecord::Migration[8.0]
  def change
    create_table :platform_staff, id: :uuid do |t|
      t.references :user, null: false, foreign_key: true, type: :uuid, index: { unique: true }
      t.string :role, null: false, default: "platform_admin"
      t.boolean :active, null: false, default: true
      t.timestamps
    end

    create_table :staff_audit_events, id: :uuid do |t|
      t.references :actor, null: false, foreign_key: { to_table: :users }, type: :uuid
      t.string :action, null: false
      t.string :target_type, null: false
      t.uuid :target_id, null: false
      t.string :reason
      t.datetime :created_at, null: false
    end
    add_index :staff_audit_events, [ :target_type, :target_id ]

    create_table :impersonation_sessions, id: :uuid do |t|
      t.references :actor, null: false, foreign_key: { to_table: :users }, type: :uuid
      t.references :target, null: false, foreign_key: { to_table: :users }, type: :uuid
      t.string :reason, null: false
      t.datetime :expires_at, null: false
      t.datetime :ended_at
      t.timestamps
    end

    change_table :users, bulk: true do |t|
      t.datetime :deletion_requested_at
      t.datetime :deletion_cancelled_at
      t.datetime :anonymized_at
    end

    add_column :project_messages, :removed_at, :datetime
  end
end
