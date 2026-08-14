# frozen_string_literal: true

module Outcomes
  class Error < DomainError; end

  class Create
    def self.call(actor:, params:)
      new(actor: actor, params: params).call
    end

    def initialize(actor:, params:)
      @actor = actor
      @params = params
    end

    def call
      organization = active_organization!
      membership = @actor.membership_for(organization)
      unless membership&.active?
        raise Error.new("An active organization membership is required", code: "forbidden", status: :forbidden)
      end

      outcome = SelfReportedOutcome.new(
        user: @actor,
        organization: organization,
        program: resolve_program(organization),
        project: resolve_project(organization),
        outcome_type: @params[:outcome_type].to_s,
        occurred_on: occurred_on,
        careerstack_contribution: @params[:careerstack_contribution].to_s,
        institution: @params[:institution].presence,
        title: @params[:title].presence,
        note: @params[:note].presence
      )
      outcome.save!
      outcome
    rescue ActiveRecord::RecordInvalid => error
      raise Error.new(error.record.errors.full_messages.to_sentence)
    end

    private

    def active_organization!
      workspace = @actor.resolved_active_workspace
      organization = workspace&.organization
      if organization.nil?
        raise Error.new("Switch to an Organization workspace to record an outcome", code: "forbidden", status: :forbidden)
      end
      organization
    end

    def occurred_on
      year = Integer(@params[:year], exception: false)
      month = Integer(@params[:month], exception: false)
      raise Error.new("Month and year are required") if year.nil? || month.nil?
      raise Error.new("Month must be between 1 and 12") unless (1..12).cover?(month)

      Date.new(year, month, 1)
    rescue Date::Error
      raise Error.new("Month and year must be a valid date")
    end

    def resolve_program(organization)
      program_id = @params[:program_id].presence
      if program_id.blank?
        membership = @actor.membership_for(organization)
        return membership&.program_filter_program
      end

      program = organization.programs.find_by(id: program_id)
      raise Error.new("Program was not found", code: "not_found", status: :not_found) if program.nil?

      program
    end

    def resolve_project(organization)
      project_id = @params[:project_id].presence
      return nil if project_id.blank?

      project = Project.find_by(id: project_id)
      unless project && project.workspace&.organization_id == organization.id
        raise Error.new("Project was not found", code: "not_found", status: :not_found)
      end

      project
    end
  end
end
