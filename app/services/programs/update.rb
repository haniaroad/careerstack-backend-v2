# frozen_string_literal: true

module Programs
  class Update
    def self.call(actor:, program:, params:)
      new(actor: actor, program: program, params: params).call
    end

    def initialize(actor:, program:, params:)
      @actor = actor
      @program = program
      @params = params.to_h.with_indifferent_access
    end

    def call
      Organizations::Access.require_writable!(@program.organization)
      raise Error, "Archived programs are read-only" if @program.archived?

      updates = {}
      if @params.key?(:name)
        name = @params[:name].to_s.strip
        raise Error, "name is required" if name.blank?

        updates[:name] = name
      end
      updates[:description] = @params[:description].presence if @params.key?(:description)
      if @params.key?(:status)
        status = @params[:status].to_s
        raise Error, "Archived programs cannot be edited" if status == Program::STATUS_ARCHIVED
        unless [ Program::STATUS_DRAFT, Program::STATUS_ACTIVE ].include?(status)
          raise Error, "status must be draft or active"
        end
        updates[:status] = status
      end

      @program.update!(updates) if updates.any?
      @program
    end
  end
end
