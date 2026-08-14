# frozen_string_literal: true

module OrganizationReports
  class Create
    def self.call(actor:, organization:, params:)
      new(actor: actor, organization: organization, params: params).call
    end

    def initialize(actor:, organization:, params:)
      @actor = actor
      @organization = organization
      @params = params
    end

    def call
      Organizations::Access.require_exportable!(@organization)
      report = @organization.organization_reports.build(
        requested_by: @actor,
        program: resolve_program,
        period_starts_on: parse_date(:period_starts_on),
        period_ends_on: parse_date(:period_ends_on),
        format: @params[:format].to_s,
        aggregate_only: ActiveModel::Type::Boolean.new.cast(@params[:aggregate_only]),
        status: OrganizationReport::STATUS_DRAFT,
        methodology_note: OrganizationReport::METHODOLOGY_NOTE
      )
      report.save!
      report
    rescue ActiveRecord::RecordInvalid => error
      raise Error.new(error.record.errors.full_messages.to_sentence)
    end

    private

    def resolve_program
      program_id = @params[:program_id].presence
      return nil if program_id.blank?

      program = Program.find_by(id: program_id)
      unless program && program.organization_id == @organization.id
        raise Error.new("Program was not found", code: "not_found", status: :not_found)
      end

      program
    end

    def parse_date(key)
      value = @params[key]
      raise Error.new("#{key.to_s.humanize} is required") if value.blank?

      Date.iso8601(value.to_s)
    rescue Date::Error
      raise Error.new("#{key.to_s.humanize} must be an ISO date")
    end
  end
end
