# frozen_string_literal: true

class AddExploreDirectoryIndexes < ActiveRecord::Migration[8.0]
  def change
    add_index :projects, [ :visibility, :status ], name: "index_projects_on_visibility_and_status"
    add_index :profiles, :display_name
    add_index :users, [ :age_status, :status ], name: "index_users_on_age_status_and_status"
  end
end
