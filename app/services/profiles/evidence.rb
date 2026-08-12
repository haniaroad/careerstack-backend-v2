# frozen_string_literal: true

module Profiles
  # Skills from project participation + artifacts from the user's submissions.
  class Evidence
    def self.call(user:)
      new(user: user).as_json
    end

    def initialize(user:)
      @user = user
    end

    def as_json
      {
        skills: skills,
        artifacts: artifacts
      }
    end

    private

    def memberships
      @memberships ||= ProjectMembership.active.includes(project: :workspace).where(user_id: @user.id)
    end

    def skills
      counts = Hash.new(0)
      levels = {}

      memberships.each do |membership|
        project = membership.project
        Array(project.skills).each do |skill|
          name = skill.to_s.strip
          next if name.blank?

          counts[name] += 1
          approved = Task.where(project_id: project.id, assignee_id: @user.id, status: Task::STATUS_APPROVED).exists?
          ai = Task.joins(:ai_reviews).where(
            project_id: project.id,
            assignee_id: @user.id,
            status: Task::STATUS_APPROVED,
            ai_reviews: { decision: AiReview::DECISION_APPROVED }
          ).exists?
          creator = Task.where(
            project_id: project.id,
            assignee_id: @user.id,
            status: Task::STATUS_APPROVED,
            creator_review_decision: Task::DECISION_APPROVED
          ).exists?

          level =
            if ai
              "ai_reviewed"
            elsif creator
              "human_reviewed"
            elsif approved || counts[name] > 1
              counts[name] > 1 ? "repeatedly_demonstrated" : "demonstrated"
            else
              "self_reported"
            end

          levels[name] = higher_level(levels[name], level)
        end
      end

      levels.map { |name, level| { name: name, level: level, evidence_count: counts[name] } }
            .sort_by { |row| row[:name].downcase }
    end

    def higher_level(current, candidate)
      order = %w[self_reported demonstrated repeatedly_demonstrated human_reviewed ai_reviewed peer_confirmed]
      return candidate if current.nil?

      order.index(candidate).to_i >= order.index(current).to_i ? candidate : current
    end

    def artifacts
      submissions = TaskSubmission.joins(:task)
                                  .where(tasks: { assignee_id: @user.id })
                                  .includes(:links, files_attachments: :blob)
                                  .order(submitted_at: :desc)
                                  .limit(50)

      rows = []
      submissions.each do |submission|
        submission.links.each do |link|
          rows << {
            kind: "link",
            url: link.url,
            label: link.url,
            submitted_at: submission.submitted_at,
            task_id: submission.task_id
          }
        end
        submission.files.each do |file|
          rows << {
            kind: "file",
            url: nil,
            label: file.filename.to_s,
            content_type: file.content_type,
            byte_size: file.byte_size,
            submitted_at: submission.submitted_at,
            task_id: submission.task_id
          }
        end
      end
      rows.first(40)
    end
  end
end
