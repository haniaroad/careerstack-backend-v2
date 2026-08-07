# frozen_string_literal: true

class CreateProjectsAndMemberships < ActiveRecord::Migration[8.0]
  def change
    create_table :projects, id: :uuid do |t|
      t.references :workspace, type: :uuid, null: false, foreign_key: true
      t.references :creator, type: :uuid, null: false, foreign_key: { to_table: :users }
      t.string :title, null: false
      t.text :summary
      t.jsonb :skills, null: false, default: []
      t.string :mode, null: false, default: "solo"
      t.string :status, null: false, default: "draft"
      t.datetime :confirmed_at
      t.datetime :cancelled_at

      t.timestamps
    end

    add_index :projects, [ :workspace_id, :status ]
    add_index :projects, [ :creator_id, :status ]

    create_table :project_memberships, id: :uuid do |t|
      t.references :project, type: :uuid, null: false, foreign_key: true
      t.references :user, type: :uuid, null: false, foreign_key: true
      t.string :role, null: false, default: "creator"
      t.string :status, null: false, default: "active"

      t.timestamps
    end

    add_index :project_memberships, [ :project_id, :user_id ], unique: true
    add_index :project_memberships, [ :user_id, :status ]
  end
end
