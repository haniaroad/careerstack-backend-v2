# frozen_string_literal: true

class SelfReportedOutcome < ApplicationRecord
  TYPE_INTERVIEW = "interview"
  TYPE_INTERNSHIP = "internship"
  TYPE_FREELANCE = "freelance_opportunity"
  TYPE_JOB = "job"
  TYPE_PROMOTION = "promotion"
  TYPE_COLLEGE = "college_acceptance"
  TYPE_TRAINING = "training_or_certification_acceptance"
  TYPE_OTHER = "other_post_secondary_acceptance"
  TYPES = [
    TYPE_INTERVIEW,
    TYPE_INTERNSHIP,
    TYPE_FREELANCE,
    TYPE_JOB,
    TYPE_PROMOTION,
    TYPE_COLLEGE,
    TYPE_TRAINING,
    TYPE_OTHER
  ].freeze

  CONTRIBUTION_YES = "yes"
  CONTRIBUTION_PARTIALLY = "partially"
  CONTRIBUTION_NOT_SURE = "not_sure"
  CONTRIBUTIONS = [ CONTRIBUTION_YES, CONTRIBUTION_PARTIALLY, CONTRIBUTION_NOT_SURE ].freeze

  REPORTING_LABEL = "self_reported"

  LABELS = {
    TYPE_INTERVIEW => "Interview",
    TYPE_INTERNSHIP => "Internship",
    TYPE_FREELANCE => "Freelance opportunity",
    TYPE_JOB => "Job",
    TYPE_PROMOTION => "Promotion",
    TYPE_COLLEGE => "College acceptance",
    TYPE_TRAINING => "Training or certification acceptance",
    TYPE_OTHER => "Other post-secondary acceptance"
  }.freeze

  belongs_to :user
  belongs_to :organization
  belongs_to :program, optional: true
  belongs_to :project, optional: true

  validates :outcome_type, inclusion: { in: TYPES }
  validates :careerstack_contribution, inclusion: { in: CONTRIBUTIONS }
  validates :occurred_on, presence: true
  validates :reporting_label, inclusion: { in: [ REPORTING_LABEL ] }
  validate :program_belongs_to_organization
  validate :project_belongs_to_organization

  before_validation :assign_reporting_label

  def label
    LABELS.fetch(outcome_type, outcome_type.humanize)
  end

  private

  def assign_reporting_label
    self.reporting_label = REPORTING_LABEL
  end

  def program_belongs_to_organization
    return if program_id.blank? || program.nil?
    return if program.organization_id == organization_id

    errors.add(:program, "must belong to the organization")
  end

  def project_belongs_to_organization
    return if project_id.blank? || project.nil?
    return if project.workspace&.organization_id == organization_id

    errors.add(:project, "must belong to the organization")
  end
end
