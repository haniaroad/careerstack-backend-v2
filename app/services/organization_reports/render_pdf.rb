# frozen_string_literal: true

require "prawn"
require "prawn/table"

module OrganizationReports
  class RenderPdf
    def self.call(report:, metrics:)
      new(report: report, metrics: metrics).call
    end

    def initialize(report:, metrics:)
      @report = report
      @metrics = metrics
    end

    def call
      Prawn::Fonts::AFM.hide_m17n_warning = true
      Prawn::Document.new(page_size: "LETTER", margin: 48) do |pdf|
        pdf.fill_color "0B0B0D"
        pdf.text @metrics.fetch("organization_name"), size: 18, style: :bold
        pdf.move_down 6
        pdf.text @report.title, size: 12, color: "475569"
        pdf.move_down 4
        pdf.text "Generated #{@metrics['generated_at']}", size: 10, color: "64748B"
        pdf.move_down 16

        pdf.text "Program overview", size: 13, style: :bold
        pdf.move_down 6
        pdf.table(overview_rows, width: pdf.bounds.width, cell_style: { size: 10, borders: [ :bottom ], border_color: "E2E8F0" })
        pdf.move_down 16

        pdf.text "Outcomes (self-reported)", size: 13, style: :bold
        pdf.move_down 6
        pdf.table(outcome_rows, width: pdf.bounds.width, cell_style: { size: 10, borders: [ :bottom ], border_color: "E2E8F0" })
        pdf.move_down 16

        unless @report.aggregate_only?
          pdf.text "Named participant details", size: 13, style: :bold
          pdf.move_down 6
          members = Array(@metrics["members"])
          if members.empty?
            pdf.text "No members in scope.", size: 10, color: "64748B"
          else
            pdf.table(member_rows(members), width: pdf.bounds.width, cell_style: { size: 9, borders: [ :bottom ], border_color: "E2E8F0" })
          end
          pdf.move_down 16
        end

        pdf.text "Methodology", size: 13, style: :bold
        pdf.move_down 6
        pdf.text @metrics["methodology_note"].to_s, size: 9, color: "475569", leading: 2
        pdf.move_down 12
        pdf.text "CareerStack snapshot — private to this organization. Date of birth is never included.", size: 8, color: "94A3B8"
      end.render
    end

    private

    def aggregates
      @metrics.fetch("aggregates")
    end

    def overview_rows
      [
        [ "Reporting period", "#{@metrics['period_starts_on']} – #{@metrics['period_ends_on']}" ],
        [ "Program", @metrics["program_name"].presence || "All programs" ],
        [ "Mode", @report.aggregate_only? ? "Aggregate only" : "Named detail" ],
        [ "Enrolled participants", aggregates["enrolled_participants"].to_s ],
        [ "Participants with a completed project", aggregates["participants_with_completed_project"].to_s ],
        [ "Participant completion rate", format_rate(aggregates["participant_completion_rate"]) ],
        [ "Projects started", aggregates["projects_started"].to_s ],
        [ "Projects completed", aggregates["projects_completed"].to_s ],
        [ "Project completion rate", format_rate(aggregates["project_completion_rate"]) ],
        [ "Tasks assigned", aggregates["tasks_assigned"].to_s ],
        [ "Tasks approved", aggregates["tasks_approved"].to_s ],
        [ "Task approval rate", format_rate(aggregates["task_approval_rate"]) ],
        [ "On-time submissions", aggregates["on_time_submissions"].to_s ],
        [ "Late submissions", aggregates["late_submissions"].to_s ],
        [ "On-time rate", format_rate(aggregates["on_time_rate"]) ],
        [ "Portfolio artifacts produced", aggregates["artifacts_produced"].to_s ],
        [ "Skills practiced", Array(aggregates["skills_practiced"]).join(", ").presence || "—" ]
      ]
    end

    def outcome_rows
      rows = [ [ "Type", "Count", "Label" ] ]
      Array(aggregates["outcomes"]).each do |type, count|
        next if count.to_i <= 0

        rows << [ SelfReportedOutcome::LABELS.fetch(type, type.humanize), count.to_s, "Self-reported" ]
      end
      rows << [ "None recorded", "0", "Self-reported" ] if rows.size == 1
      rows
    end

    def member_rows(members)
      rows = [ [ "Name", "Email", "Role", "Age status", "Programs" ] ]
      members.each do |member|
        rows << [
          member["display_name"].to_s,
          member["email"].to_s,
          member["role"].to_s,
          member["age_status"].to_s,
          Array(member["program_names"]).join(", ")
        ]
      end
      rows
    end

    def format_rate(value)
      return "—" if value.nil?

      "#{(value.to_f * 100).round(1)}%"
    end
  end
end
