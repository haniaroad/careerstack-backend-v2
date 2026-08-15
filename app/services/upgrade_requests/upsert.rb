# frozen_string_literal: true

module UpgradeRequests
  class Upsert
    STAFF_INBOX = "hello@careerstack.co"

    def self.call(organization:, admin:, params:)
      new(organization: organization, admin: admin, params: params).call
    end

    def initialize(organization:, admin:, params:)
      @organization = organization
      @admin = admin
      @params = params.to_h.with_indifferent_access
    end

    def call
      Organizations::Access.require_writable!(@organization)
      attributes = {
        requesting_user: @admin,
        expected_participants: required(:expected_participants),
        expected_projects_or_cohorts: required(:expected_projects_or_cohorts),
        timeline: required(:timeline),
        notes: @params[:notes].presence,
        status: OrganizationUpgradeRequest::STATUS_OPEN,
        notified_at: Time.current
      }

      request = @organization.open_upgrade_request
      if request
        request.update!(attributes)
      else
        request = @organization.upgrade_requests.create!(attributes)
      end

      Rails.logger.info(
        {
          event: "organization_upgrade_request",
          organization_id: @organization.id,
          upgrade_request_id: request.id,
          staff_inbox: STAFF_INBOX
        }.to_json
      )

      payload = Notifications::Hook.org_payload(@organization)
      Notifications::Hook.emit(
        event_key: "upgrade_request_received",
        actor: nil,
        recipients: [ @admin ],
        source: request,
        organization: @organization,
        payload: payload
      )
      Notifications::Hook.emit(
        event_key: "upgrade_request_received",
        actor: @admin,
        recipients: [ { email: Notifications::Catalog::STAFF_INBOX } ],
        source: request,
        organization: @organization,
        payload: payload
      )

      request
    end

    private

    def required(key)
      value = @params[key].to_s.strip
      raise Error, "#{key} is required" if value.blank?

      value
    end
  end
end
