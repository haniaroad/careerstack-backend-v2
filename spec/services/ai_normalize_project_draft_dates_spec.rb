# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::NormalizeProjectDraftDates do
  let(:today) { Date.current }

  it "bumps today/past end dates using time_available" do
    payload = {
      "project_end_date" => today.iso8601,
      "proposed_tasks" => [
        {
          "title" => "Task",
          "summary" => "Do it",
          "recommended_due_date" => today.iso8601,
          "submission_expectations" => "Link"
        }
      ]
    }

    result = described_class.call(payload, time_available: "1 month")
    end_date = Date.iso8601(result["project_end_date"])
    due = Date.iso8601(result["proposed_tasks"].first["recommended_due_date"])

    expect(end_date).to eq(today + 30)
    expect(due).to be > today
    expect(due).to be <= end_date
  end

  it "leaves already-valid future dates alone" do
    end_date = today + 21
    due = today + 10
    payload = {
      "project_end_date" => end_date.iso8601,
      "proposed_tasks" => [
        {
          "title" => "Task",
          "summary" => "Do it",
          "recommended_due_date" => due.iso8601,
          "submission_expectations" => "Link"
        }
      ]
    }

    result = described_class.call(payload, time_available: "2 weeks")
    expect(result["project_end_date"]).to eq(end_date.iso8601)
    expect(result["proposed_tasks"].first["recommended_due_date"]).to eq(due.iso8601)
  end
end
