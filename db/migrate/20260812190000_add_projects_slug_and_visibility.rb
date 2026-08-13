# frozen_string_literal: true

class AddProjectsSlugAndVisibility < ActiveRecord::Migration[8.0]
  def up
    add_column :projects, :slug, :string
    add_index :projects, :slug, unique: true
    add_column :projects, :visibility, :string, null: false, default: "public"

    say_with_time "backfill project slugs and visibility" do
      Project.reset_column_information
      Project.includes(:workspace).find_each do |project|
        visibility = project.workspace&.organization? ? "private" : "public"
        updates = { visibility: visibility }

        if project.slug.blank?
          base = project.title.to_s.downcase.gsub(/[^a-z0-9]+/, "-").gsub(/\A-+|-+\z/, "")
          base = "project" if base.blank?
          candidate = base
          suffix = 0
          while Project.where(slug: candidate).where.not(id: project.id).exists?
            suffix += 1
            candidate = "#{base}-#{suffix}"
          end
          updates[:slug] = candidate
        end

        project.update_columns(updates)
      end
    end

    change_column_null :projects, :slug, false
    change_column_default :projects, :visibility, from: "public", to: nil
  end

  def down
    remove_index :projects, :slug
    remove_column :projects, :slug
    remove_column :projects, :visibility
  end
end
