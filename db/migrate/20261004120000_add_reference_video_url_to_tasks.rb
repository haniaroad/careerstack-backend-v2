# frozen_string_literal: true

class AddReferenceVideoUrlToTasks < ActiveRecord::Migration[8.0]
  def change
    add_column :tasks, :reference_video_url, :string
  end
end
