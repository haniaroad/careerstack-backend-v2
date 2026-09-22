# frozen_string_literal: true

class AddPeerReviews < ActiveRecord::Migration[8.0]
  def up
    create_table :peer_reviews, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :project, type: :uuid, null: false, foreign_key: true
      t.references :reviewer, type: :uuid, null: false, foreign_key: { to_table: :users }
      t.references :reviewee, type: :uuid, null: false, foreign_key: { to_table: :users }
      t.string :status, null: false, default: "available"
      t.integer :rating
      t.text :comment
      t.datetime :submitted_at
      t.datetime :hidden_at
      t.timestamps
    end
    add_index :peer_reviews, [ :project_id, :reviewer_id, :reviewee_id ],
              unique: true, name: "index_peer_reviews_on_project_reviewer_reviewee"
    add_index :peer_reviews, [ :reviewee_id, :status ]
    add_index :peer_reviews, [ :reviewer_id, :status ]

    create_table :peer_review_reports, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :peer_review, type: :uuid, null: false, foreign_key: true
      t.references :reporter, type: :uuid, null: false, foreign_key: { to_table: :users }
      t.string :report_type, null: false
      t.string :reason_category, null: false
      t.text :details
      t.string :status, null: false, default: "open"
      t.timestamps
    end
    add_index :peer_review_reports, [ :peer_review_id, :reporter_id ],
              unique: true, where: "status = 'open'", name: "index_peer_review_reports_open_per_reporter"

    execute <<~SQL.squish
      INSERT INTO peer_reviews (id, project_id, reviewer_id, reviewee_id, status, created_at, updated_at)
      SELECT gen_random_uuid(), p.id, a.user_id, b.user_id, 'available', NOW(), NOW()
      FROM projects p
      INNER JOIN project_memberships a ON a.project_id = p.id AND a.status = 'active'
      INNER JOIN project_memberships b ON b.project_id = p.id AND b.status = 'active' AND a.user_id <> b.user_id
      WHERE p.status = 'completed' AND p.mode = 'team'
      ON CONFLICT (project_id, reviewer_id, reviewee_id) DO NOTHING
    SQL
  end

  def down
    drop_table :peer_review_reports
    drop_table :peer_reviews
  end
end
