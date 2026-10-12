class AddCreatorToOrganizations < ActiveRecord::Migration[8.0]
  def up
    # Add creator_id column (nullable during migration to allow existing orgs)
    # add_reference automatically creates an index
    add_reference :organizations, :creator, null: true, foreign_key: { to_table: :users }, type: :uuid

    # Attempt to backfill creator_id from authoritative audit history.
    # Staff audit events track admin actions with actor_id. If an organization
    # creation event exists, use that actor as the creator.
    #
    # For organizations without audit trail, leave creator_id NULL.
    # The application will flag these for manual review and block the affected
    # user from creating another organization until resolved.
    #
    # DO NOT infer creator from earliest admin membership; that is not authoritative.

    reversible do |dir|
      dir.up do
        # Check if StaffAuditEvent table exists and has organization_created events
        if ActiveRecord::Base.connection.table_exists?('staff_audit_events')
          # Backfill from audit events where action = 'organization_created'
          execute <<-SQL.squish
            UPDATE organizations
            SET creator_id = staff_audit_events.actor_id
            FROM staff_audit_events
            WHERE staff_audit_events.target_type = 'Organization'
              AND staff_audit_events.target_id = organizations.id
              AND staff_audit_events.action = 'organization_created'
          SQL
        end

        # Log organizations that couldn't be backfilled
        null_count = Organization.where(creator_id: nil).count
        if null_count > 0
          say "WARNING: #{null_count} organization(s) have NULL creator_id."
          say "These require manual review. Affected users will be blocked from"
          say "creating additional organizations until creator attribution is resolved."
        end
      end
    end
  end

  def down
    remove_reference :organizations, :creator, foreign_key: true
  end
end
