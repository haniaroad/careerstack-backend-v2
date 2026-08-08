# frozen_string_literal: true

class AddTeamJoiningSupport < ActiveRecord::Migration[8.0]
  def change
    change_table :projects, bulk: true do |t|
      t.string :joining_mode
      t.integer :capacity
    end

    change_table :project_memberships, bulk: true do |t|
      t.string :participant_role
      t.string :join_source
    end

    create_table :project_membership_events, id: :uuid do |t|
      t.uuid :project_membership_id, null: false
      t.uuid :project_id, null: false
      t.uuid :user_id, null: false
      t.uuid :actor_user_id
      t.string :event_type, null: false
      t.string :reason_category
      t.text :reason_detail
      t.string :join_source
      t.string :participant_role
      t.datetime :created_at, null: false
    end
    add_index :project_membership_events, :project_membership_id
    add_index :project_membership_events, :project_id
    add_index :project_membership_events, :user_id
    add_foreign_key :project_membership_events, :project_memberships
    add_foreign_key :project_membership_events, :projects
    add_foreign_key :project_membership_events, :users
    add_foreign_key :project_membership_events, :users, column: :actor_user_id

    create_table :project_applications, id: :uuid do |t|
      t.uuid :project_id, null: false
      t.uuid :applicant_id, null: false
      t.string :requested_role, null: false
      t.text :motivation, null: false
      t.boolean :availability_confirmed, null: false, default: false
      t.jsonb :skills, null: false, default: []
      t.string :portfolio_url
      t.string :github_url
      t.string :resume_url
      t.string :status, null: false, default: "pending"
      t.text :rejection_reason
      t.uuid :reviewed_by_id
      t.datetime :reviewed_at
      t.datetime :created_at, null: false
      t.datetime :updated_at, null: false
    end
    add_index :project_applications, :project_id
    add_index :project_applications, :applicant_id
    add_index :project_applications, [ :project_id, :applicant_id, :status ]
    add_foreign_key :project_applications, :projects
    add_foreign_key :project_applications, :users, column: :applicant_id
    add_foreign_key :project_applications, :users, column: :reviewed_by_id

    create_table :project_invitations, id: :uuid do |t|
      t.uuid :project_id, null: false
      t.uuid :inviter_id, null: false
      t.uuid :invitee_id, null: false
      t.string :requested_role, null: false
      t.string :status, null: false, default: "pending"
      t.datetime :responded_at
      t.datetime :created_at, null: false
      t.datetime :updated_at, null: false
    end
    add_index :project_invitations, :project_id
    add_index :project_invitations, :invitee_id
    add_index :project_invitations, [ :project_id, :invitee_id, :status ]
    add_foreign_key :project_invitations, :projects
    add_foreign_key :project_invitations, :users, column: :inviter_id
    add_foreign_key :project_invitations, :users, column: :invitee_id

    change_column_null :tasks, :assignee_id, true
  end
end
