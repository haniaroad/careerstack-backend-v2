# frozen_string_literal: true

class AddOrganizationAdministration < ActiveRecord::Migration[8.0]
  def up
    add_column :programs, :status, :string, null: false, default: "active"
    add_column :programs, :description, :text
    add_index :programs, [ :organization_id, :status ]

    add_column :organizations, :workspace_status, :string, null: false, default: "active"
    add_column :organizations, :offboarding_started_at, :datetime
    add_column :organizations, :offboarding_ends_on, :date
    add_index :organizations, :workspace_status

    add_column :organization_memberships, :status, :string, null: false, default: "active"
    add_column :organization_memberships, :removed_at, :datetime
    add_column :organization_memberships, :removed_reason, :string
    add_column :organization_memberships, :removed_by_user_id, :uuid
    add_index :organization_memberships, [ :organization_id, :status ]

    add_column :projects, :program_id, :uuid
    add_index :projects, :program_id

    create_table :program_enrollments, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :organization_membership, type: :uuid, null: false, foreign_key: true
      t.references :program, type: :uuid, null: false, foreign_key: true
      t.timestamps
    end
    add_index :program_enrollments, [ :organization_membership_id, :program_id ], unique: true, name: "index_program_enrollments_on_membership_and_program"

    create_table :organization_upgrade_requests, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :organization, type: :uuid, null: false, foreign_key: true
      t.references :requesting_user, type: :uuid, null: false, foreign_key: { to_table: :users }
      t.string :expected_participants, null: false
      t.string :expected_projects_or_cohorts, null: false
      t.string :timeline, null: false
      t.text :notes
      t.string :status, null: false, default: "open"
      t.datetime :notified_at
      t.timestamps
    end
    add_index :organization_upgrade_requests, :organization_id, unique: true, where: "status = 'open'", name: "index_org_upgrade_requests_one_open"

    add_foreign_key :projects, :programs
    add_foreign_key :organization_memberships, :users, column: :removed_by_user_id

    say_with_time "backfill program enrollments from memberships.program_id" do
      ProgramEnrollment.reset_column_information
      OrganizationMembership.reset_column_information
      OrganizationMembership.where.not(program_id: nil).find_each do |membership|
        ProgramEnrollment.find_or_create_by!(
          organization_membership_id: membership.id,
          program_id: membership.program_id
        )
      end
    end

    say_with_time "backfill organization project programs" do
      Project.reset_column_information
      Program.reset_column_information
      Organization.includes(:workspace, :programs).find_each do |organization|
        workspace = organization.workspace
        next if workspace.nil?

        projects = Project.where(workspace_id: workspace.id, program_id: nil)
        next if projects.none?

        program = organization.programs.where(status: "active").order(:created_at).first ||
          organization.programs.order(:created_at).first ||
          organization.programs.create!(name: "General", status: "active")

        projects.update_all(program_id: program.id)
      end
    end
  end

  def down
    remove_foreign_key :projects, :programs
    remove_foreign_key :organization_memberships, column: :removed_by_user_id

    drop_table :organization_upgrade_requests
    drop_table :program_enrollments

    remove_index :projects, :program_id
    remove_column :projects, :program_id

    remove_index :organization_memberships, [ :organization_id, :status ]
    remove_column :organization_memberships, :removed_by_user_id
    remove_column :organization_memberships, :removed_reason
    remove_column :organization_memberships, :removed_at
    remove_column :organization_memberships, :status

    remove_index :organizations, :workspace_status
    remove_column :organizations, :offboarding_ends_on
    remove_column :organizations, :offboarding_started_at
    remove_column :organizations, :workspace_status

    remove_index :programs, [ :organization_id, :status ]
    remove_column :programs, :description
    remove_column :programs, :status
  end
end
