# frozen_string_literal: true

module Invitations
  # Issues an invitation on behalf of an organization admin or manager.
  # Inviting somebody never consumes credits.
  class Create
    MAX_TTL = 90.days

    Result = Struct.new(:invitation, :raw_token, keyword_init: true)

    def self.call(actor:, params:)
      new(actor: actor, params: params).call
    end

    def initialize(actor:, params:)
      @actor = actor
      @params = params.to_h.with_indifferent_access
    end

    def call
      raise Error, "organization_id is required" if @params[:organization_id].blank?

      organization = Organization.find(@params[:organization_id])
      membership = @actor.membership_for(organization)

      unless membership&.staff?
        raise Error.new(
          "Organization administrator access is required",
          code: "forbidden",
          status: :forbidden
        )
      end

      invitation, raw_token = Invitation.issue!(
        organization: organization,
        program: resolve_program(organization),
        email: @params[:email],
        created_by_user: @actor,
        role: resolve_role,
        expires_at: resolve_expiry
      )

      Result.new(invitation: invitation, raw_token: raw_token)
    end

    private

    def resolve_program(organization)
      program_id = @params[:program_id]
      return nil if program_id.blank?

      organization.programs.find(program_id)
    end

    def resolve_role
      role = @params[:role].presence || OrganizationMembership::PARTICIPANT
      raise Error, "role must be one of #{OrganizationMembership::ROLES.join(', ')}" unless OrganizationMembership::ROLES.include?(role)

      role
    end

    def resolve_expiry
      days = @params[:expires_in_days]
      return Invitation::DEFAULT_TTL.from_now if days.blank?

      days = Integer(days, exception: false)
      raise Error, "expires_in_days must be a positive number of days" if days.nil? || days <= 0
      raise Error, "expires_in_days cannot exceed #{MAX_TTL.in_days.to_i}" if days.days > MAX_TTL

      days.days.from_now
    end
  end
end
