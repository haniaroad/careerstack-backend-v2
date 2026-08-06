# frozen_string_literal: true

class CreateCreditLotsAndBillingTables < ActiveRecord::Migration[8.0]
  def up
    create_table :credit_lots, id: :uuid do |t|
      t.string :owner_type, null: false
      t.uuid :owner_id, null: false
      t.string :source, null: false
      t.integer :original_amount, null: false
      t.integer :remaining, null: false
      t.string :stripe_payment_ref
      t.datetime :granted_at, null: false
      t.timestamps
    end
    add_index :credit_lots, [ :owner_type, :owner_id, :granted_at ]
    add_index :credit_lots, :stripe_payment_ref, unique: true, where: "stripe_payment_ref IS NOT NULL"

    add_column :credit_ledger_entries, :related_type, :string
    add_column :credit_ledger_entries, :related_id, :uuid
    add_column :credit_ledger_entries, :credit_lot_id, :uuid
    add_foreign_key :credit_ledger_entries, :credit_lots
    add_index :credit_ledger_entries, [ :related_type, :related_id ]

    create_table :stripe_customers, id: :uuid do |t|
      t.references :user, type: :uuid, null: false, foreign_key: true, index: { unique: true }
      t.string :stripe_customer_id, null: false
      t.timestamps
    end
    add_index :stripe_customers, :stripe_customer_id, unique: true

    create_table :credit_purchases, id: :uuid do |t|
      t.references :user, type: :uuid, null: false, foreign_key: true
      t.references :credit_lot, type: :uuid, foreign_key: true
      t.string :stripe_checkout_session_id, null: false
      t.string :stripe_payment_intent_id
      t.string :status, null: false, default: "pending"
      t.integer :credits, null: false, default: 3
      t.integer :amount_cents, null: false, default: 2000
      t.string :currency, null: false, default: "usd"
      t.datetime :completed_at
      t.timestamps
    end
    add_index :credit_purchases, :stripe_checkout_session_id, unique: true
    add_index :credit_purchases, :status

    create_table :credit_refund_requests, id: :uuid do |t|
      t.references :user, type: :uuid, null: false, foreign_key: true
      t.references :credit_purchase, type: :uuid, null: false, foreign_key: true
      t.string :status, null: false, default: "submitted"
      t.text :reason
      t.integer :unused_credits_at_request, null: false
      t.datetime :resolved_at
      t.timestamps
    end
    add_index :credit_refund_requests, :status

    create_table :stripe_webhook_events, id: :uuid do |t|
      t.string :stripe_event_id, null: false
      t.string :event_type, null: false
      t.string :processing_status, null: false, default: "processed"
      t.text :error_message
      t.timestamps
    end
    add_index :stripe_webhook_events, :stripe_event_id, unique: true

    backfill_lots_from_existing_grants
  end

  def down
    drop_table :stripe_webhook_events
    drop_table :credit_refund_requests
    drop_table :credit_purchases
    drop_table :stripe_customers
    remove_foreign_key :credit_ledger_entries, :credit_lots
    remove_index :credit_ledger_entries, [ :related_type, :related_id ]
    remove_column :credit_ledger_entries, :credit_lot_id
    remove_column :credit_ledger_entries, :related_id
    remove_column :credit_ledger_entries, :related_type
    drop_table :credit_lots
  end

  private

  def backfill_lots_from_existing_grants
    say_with_time "backfill credit_lots from existing grant entries" do
      execute <<~SQL.squish
        INSERT INTO credit_lots (
          id, owner_type, owner_id, source, original_amount, remaining,
          granted_at, created_at, updated_at
        )
        SELECT
          gen_random_uuid(),
          owner_type,
          owner_id,
          reason,
          amount,
          amount,
          created_at,
          NOW(),
          NOW()
        FROM credit_ledger_entries
        WHERE event = 'grant' AND amount > 0
      SQL

      execute <<~SQL.squish
        UPDATE credit_ledger_entries AS e
        SET credit_lot_id = l.id
        FROM credit_lots AS l
        WHERE e.event = 'grant'
          AND e.owner_type = l.owner_type
          AND e.owner_id = l.owner_id
          AND e.reason = l.source
          AND e.amount = l.original_amount
          AND e.created_at = l.granted_at
          AND e.credit_lot_id IS NULL
      SQL
    end
  end
end
