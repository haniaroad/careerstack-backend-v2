# frozen_string_literal: true

require "csv"

module PlatformAdmin
  class ImportAccounts
    MAX_ROWS = 200

    def self.call!(actor:, csv_text:, organization_id: nil, reason:)
      new(actor:, csv_text:, organization_id:, reason:).call!
    end

    def initialize(actor:, csv_text:, organization_id:, reason:)
      @actor = actor
      @csv_text = csv_text.to_s
      @organization_id = organization_id.presence
      @reason = reason.to_s.strip
    end

    def call!
      raise DomainError.new("A reason is required", code: "validation_error") if @reason.blank?

      table = parse!
      rows = table.filter_map.with_index do |row, index|
        email = cell(row, "email")
        next if email.blank? && cell(row, "name").blank? && cell(row, "role").blank?

        import_row(row, index + 2)
      end

      target = @organization_id.present? ? Organization.find_by(id: @organization_id) : @actor
      target ||= @actor
      Audit.record!(
        actor: @actor,
        action: "import_accounts",
        target: target,
        reason: "#{@reason} (#{summary(rows)})"
      )
      { rows: rows }
    end

    private

    def parse!
      table = CSV.parse(@csv_text, headers: true, liberal_parsing: false)
      headers = Array(table.headers).map { |header| header.to_s.strip.downcase }
      unless headers.include?("email")
        raise DomainError.new("The CSV must include an email column", code: "validation_error")
      end
      if table.size > MAX_ROWS
        raise DomainError.new("A CSV can include at most #{MAX_ROWS} people", code: "validation_error")
      end

      table
    rescue CSV::MalformedCSVError
      raise DomainError.new("The CSV could not be read", code: "validation_error")
    end

    def import_row(row, line)
      role = @organization_id.present? ? cell(row, "role").presence : nil
      result = ProvisionAccount.call!(
        actor: @actor,
        email: cell(row, "email"),
        organization_id: @organization_id,
        role: role,
        reason: @reason
      )
      result.stringify_keys.merge("line" => line)
    rescue DomainError => error
      { "line" => line, "email" => cell(row, "email"), "status" => "error", "message" => error.message }
    end

    def cell(row, name)
      value = row.headers.lazy.filter_map { |header|
        header.to_s.strip.downcase == name ? row[header] : nil
      }.first
      value.to_s.strip
    end

    def summary(rows)
      counts = rows.group_by { |row| row[:status] || row["status"] }.transform_values(&:size)
      "created #{counts['created'].to_i}, existing #{counts['already_exists'].to_i}, failed #{counts['error'].to_i}"
    end
  end
end
