# frozen_string_literal: true

module Credits
  # Grants three pooled organization trial credits at $0. The limit is one org
  # trial per verified adult ever, not per organization, so the idempotency key
  # is scoped to the creating user: a second organization gets no grant.
  class GrantOrganizationTrial
    include IdempotentGrant

    AMOUNT = 3
    REASON = "organization_trial"

    def self.call(user:, organization:)
      new(user: user, organization: organization).call
    end

    def initialize(user:, organization:)
      @user = user
      @organization = organization
    end

    def call
      return false unless @user.adult?
      return false if @user.organization_trial_granted?

      granted = record_grant(
        owner: @organization,
        amount: AMOUNT,
        reason: REASON,
        idempotency_key: self.class.idempotency_key_for(@user),
        actor_user: @user
      )

      @user.update!(organization_trial_granted: true)
      granted
    end

    def self.idempotency_key_for(user)
      "organization_trial_user:#{user.id}"
    end
  end
end
