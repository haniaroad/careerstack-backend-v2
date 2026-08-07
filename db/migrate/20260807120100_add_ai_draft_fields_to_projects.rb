# frozen_string_literal: true

class AddAiDraftFieldsToProjects < ActiveRecord::Migration[8.0]
  def change
    change_table :projects, bulk: true do |t|
      t.text :objective
      t.string :project_type
      t.string :expected_duration
      t.date :ends_on
      t.text :definition_of_done
      t.jsonb :roles_needed, null: false, default: []
      t.jsonb :proposed_tasks, null: false, default: []
      t.text :submission_expectations
      t.string :source, null: false, default: "manual"
      t.datetime :ai_generation_succeeded_at
    end
  end
end
