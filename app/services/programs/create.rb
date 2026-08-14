# frozen_string_literal: true

module Programs
  class Create
    def self.call(actor:, organization:, params:)
      new(actor: actor, organization: organization, params: params).call
    end

    def initialize(actor:, organization:, params:)
      @actor = actor
      @organization = organization
      @params = params.to_h.with_indifferent_access
    end

    def call
      Organizations::Access.require_writable!(@organization)
      name = @params[:name].to_s.strip
      raise Error, "name is required" if name.blank?

      status = @params[:status].presence || Program::STATUS_DRAFT
      unless Program::STATUSES.include?(status) && status != Program::STATUS_ARCHIVED
        raise Error, "status must be draft or active"
      end

      @organization.programs.create!(
        name: name,
        description: @params[:description].presence,
        status: status
      )
    end
  end
end
