# frozen_string_literal: true

class AddStagingUsability < ActiveRecord::Migration[8.0]
  def change
    create_table :home_warning_dismissals, id: :uuid do |t|
      t.references :user, null: false, foreign_key: true, type: :uuid
      t.references :project, null: false, foreign_key: true, type: :uuid
      t.string :phase, null: false
      t.datetime :dismissed_at, null: false
      t.timestamps
    end

    add_index :home_warning_dismissals, [ :user_id, :project_id, :phase ], unique: true,
              name: "index_home_warning_dismissals_on_user_project_phase"

    add_column :invitations, :last_sent_at, :datetime
    reversible do |dir|
      dir.up { execute "UPDATE invitations SET last_sent_at = created_at WHERE last_sent_at IS NULL" }
    end
    change_column_null :invitations, :last_sent_at, false
  end
end
