# frozen_string_literal: true

class AddProjectLifecycleTimestamps < ActiveRecord::Migration[8.0]
  def up
    change_table :projects, bulk: true do |t|
      t.datetime :completed_at
      t.datetime :expired_at
    end

    # Active projects must have an end date for phase/expiration gates. Drafts may still omit ends_on.
    execute <<~SQL.squish
      UPDATE projects
      SET ends_on = COALESCE(confirmed_at::date, CURRENT_DATE) + 30
      WHERE status = 'active'
        AND ends_on IS NULL
    SQL
  end

  def down
    remove_column :projects, :completed_at
    remove_column :projects, :expired_at
  end
end
