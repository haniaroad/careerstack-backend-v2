# frozen_string_literal: true

class AddStaffProvisionedToProjects < ActiveRecord::Migration[8.1]
  def change
    add_column :projects, :staff_provisioned, :boolean, null: false, default: false
  end
end
