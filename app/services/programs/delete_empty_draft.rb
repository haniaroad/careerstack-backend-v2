# frozen_string_literal: true

module Programs
  class DeleteEmptyDraft
    def self.call(program:)
      new(program: program).call
    end

    def initialize(program:)
      @program = program
    end

    def call
      Organizations::Access.require_writable!(@program.organization)
      raise Error, "Only draft programs can be deleted" unless @program.draft?
      unless @program.empty_for_delete?
        raise Error, "Only empty draft programs can be deleted; archive this program instead"
      end

      @program.destroy!
    end
  end
end
