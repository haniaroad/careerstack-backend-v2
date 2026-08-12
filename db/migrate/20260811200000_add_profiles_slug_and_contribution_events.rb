# frozen_string_literal: true

class AddProfilesSlugAndContributionEvents < ActiveRecord::Migration[8.0]
  def up
    add_column :profiles, :slug, :string
    add_index :profiles, :slug, unique: true

    # Backfill after column exists; AssignSlug is available once app code loads.
    say_with_time "backfill profile slugs" do
      Profile.reset_column_information
      Profile.find_each do |profile|
        next if profile.slug.present?

        base = profile.display_name.to_s.downcase.gsub(/[^a-z0-9]+/, "-").gsub(/\A-+|-+\z/, "")
        base = "member" if base.blank?
        candidate = base
        suffix = 0
        while Profile.where(slug: candidate).where.not(id: profile.id).exists?
          suffix += 1
          candidate = "#{base}-#{suffix}"
        end
        profile.update_columns(slug: candidate)
      end
    end

    change_column_null :profiles, :slug, false

    create_table :contribution_events, id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
      t.uuid :user_id, null: false
      t.string :kind, null: false
      t.datetime :occurred_at, null: false
      t.string :subject_type, null: false
      t.uuid :subject_id, null: false
      t.string :workspace_kind, null: false
      t.boolean :private_org, null: false, default: false
      t.string :idempotency_key, null: false
      t.datetime :created_at, null: false
      t.datetime :updated_at, null: false

      t.index :user_id
      t.index :idempotency_key, unique: true
      t.index [ :user_id, :occurred_at ]
      t.index [ :subject_type, :subject_id ]
      t.index :kind
    end

    add_foreign_key :contribution_events, :users
  end

  def down
    remove_foreign_key :contribution_events, :users
    drop_table :contribution_events
    remove_index :profiles, :slug
    remove_column :profiles, :slug
  end
end
