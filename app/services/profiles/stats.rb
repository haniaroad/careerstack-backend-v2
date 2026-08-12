# frozen_string_literal: true

module Profiles
  # Derived contribution stats and activity sparkline. Never user-editable.
  class Stats
    SPARKLINE_WEEKS = 26

    def self.call(user:)
      new(user: user).as_json
    end

    def initialize(user:)
      @user = user
    end

    def as_json
      {
        projects_completed: projects_completed,
        active_projects: active_projects,
        tasks_approved: tasks_approved,
        on_time_submission_rate: on_time_submission_rate,
        late_submissions: late_submissions_count,
        unsubmitted_tasks: unsubmitted_tasks_count,
        ai_approved_tasks: specialized_count(ai_approved_tasks_count),
        creator_reviewed_approved_tasks: specialized_count(creator_reviewed_approved_count),
        average_creator_review_hours: average_creator_review_hours,
        activity: activity_sparkline
      }
    end

    private

    def membership_project_ids
      @membership_project_ids ||= ProjectMembership.active.where(user_id: @user.id).select(:project_id)
    end

    def projects_completed
      Project.where(id: membership_project_ids, status: Project::STATUS_COMPLETED).count
    end

    def active_projects
      Project.where(id: membership_project_ids, status: Project::STATUS_ACTIVE).count
    end

    def assigned_tasks
      Task.where(assignee_id: @user.id)
    end

    def tasks_approved
      assigned_tasks.where(status: Task::STATUS_APPROVED).count
    end

    def submitted_tasks_scope
      assigned_tasks.where.not(first_submitted_at: nil)
    end

    def on_time_submission_rate
      total = submitted_tasks_scope.count
      return nil if total.zero?

      on_time = submitted_tasks_scope.where(on_time: true).count
      { numerator: on_time, denominator: total, rate: (on_time.to_f / total).round(3) }
    end

    def late_submissions_count
      count = submitted_tasks_scope.where(on_time: false).count
      count.positive? ? count : nil
    end

    def unsubmitted_tasks_count
      count = assigned_tasks.where(status: Task::STATUS_PENDING).count
      count.positive? ? count : nil
    end

    def ai_approved_tasks_count
      Task.joins(:ai_reviews)
          .where(assignee_id: @user.id, status: Task::STATUS_APPROVED)
          .where(ai_reviews: { decision: AiReview::DECISION_APPROVED })
          .distinct
          .count
    end

    def creator_reviewed_approved_count
      assigned_tasks.where(
        status: Task::STATUS_APPROVED,
        creator_review_decision: Task::DECISION_APPROVED
      ).count
    end

    def average_creator_review_hours
      rows = assigned_tasks.where.not(creator_reviewed_at: nil).where.not(first_submitted_at: nil)
      return nil if rows.none?

      # Only when this user has creator history reviewing others — average review
      # time as a creator is about tasks they reviewed, not their own.
      reviewed = Task.where(creator_reviewed_by_id: @user.id).where.not(creator_reviewed_at: nil).where.not(first_submitted_at: nil)
      return nil if reviewed.none?

      hours = reviewed.filter_map do |task|
        next if task.first_submitted_at.nil? || task.creator_reviewed_at.nil?

        ((task.creator_reviewed_at - task.first_submitted_at) / 1.hour).round(1)
      end
      return nil if hours.empty?

      (hours.sum / hours.size.to_f).round(1)
    end

    def specialized_count(value)
      value.positive? ? value : nil
    end

    def activity_sparkline
      since = SPARKLINE_WEEKS.weeks.ago.beginning_of_week
      events = ContributionEvent.where(user_id: @user.id).where("occurred_at >= ?", since)

      buckets = Hash.new(0)
      events.find_each do |event|
        key = event.occurred_at.utc.to_date.beginning_of_week(:monday).iso8601
        buckets[key] += 1
      end

      SPARKLINE_WEEKS.times.map do |offset|
        week_start = (since + offset.weeks).to_date.beginning_of_week(:monday)
        iso = week_start.iso8601
        { week_start: iso, count: buckets[iso] || 0 }
      end
    end
  end
end
