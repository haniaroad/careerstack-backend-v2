# frozen_string_literal: true

class AddFirstRunTipDismissals < ActiveRecord::Migration[8.0]
  def change
    create_table :first_run_tip_dismissals, id: :uuid do |t|
      t.references :user, null: false, foreign_key: true, type: :uuid
      t.string :tip_key, null: false
      t.datetime :dismissed_at, null: false
      t.timestamps
    end

    add_index :first_run_tip_dismissals, [ :user_id, :tip_key ], unique: true
  end
end
