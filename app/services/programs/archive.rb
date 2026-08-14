# frozen_string_literal: true

module Programs
  class Archive
    def self.call(program:)
      new(program: program).call
    end

    def initialize(program:)
      @program = program
    end

    def call
      Organizations::Access.require_writable!(@program.organization)
      raise Error, "Program is already archived" if @program.archived?

      @program.update!(status: Program::STATUS_ARCHIVED)
      @program
    end
  end
end
