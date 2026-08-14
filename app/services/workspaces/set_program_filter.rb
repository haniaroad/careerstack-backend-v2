# frozen_string_literal: true

module Workspaces
  class SetProgramFilter
    def self.call(user:, mode:, program_id: nil)
      new(user: user, mode: mode, program_id: program_id).call
    end

    def initialize(user:, mode:, program_id:)
      @user = user
      @mode = mode.to_s
      @program_id = program_id
    end

    def call
      workspace = @user.resolved_active_workspace
      raise DomainError.new("No active workspace", code: "no_workspace") if workspace.nil?
      unless workspace.organization?
        raise DomainError.new("Program filter is only available in an Organization workspace", code: "validation_error")
      end

      membership = @user.membership_for(workspace.organization)
      raise DomainError.new("Not a member of this organization", code: "forbidden", status: :forbidden) if membership.nil?

      case @mode
      when "all"
        membership.update!(program_filter_program: nil)
      when "program"
        raise DomainError.new("program_id is required", code: "validation_error") if @program_id.blank?

        program = workspace.organization.programs.find(@program_id)
        unless program.active? || program.archived?
          raise DomainError.new("That program cannot be used as a filter", code: "validation_error")
        end
        membership.update!(program_filter_program: program)
      else
        raise DomainError.new("mode must be all or program", code: "validation_error")
      end

      membership
    end
  end
end
