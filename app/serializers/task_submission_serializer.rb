# frozen_string_literal: true

class TaskSubmissionSerializer
  def self.call(submission)
    new(submission).as_json
  end

  def initialize(submission)
    @submission = submission
  end

  def as_json
    {
      id: @submission.id,
      task_id: @submission.task_id,
      attempt_number: @submission.attempt_number,
      body: @submission.body,
      content_fingerprint: @submission.content_fingerprint,
      submitted_at: @submission.submitted_at,
      links: @submission.links.map { |l| { id: l.id, url: l.url } },
      files: @submission.files.map { |f| file_json(f) }
    }
  end

  private

  def file_json(attachment)
    blob = attachment.blob
    {
      id: attachment.id,
      filename: blob.filename.to_s,
      content_type: blob.content_type,
      byte_size: blob.byte_size,
      signed_id: blob.signed_id
    }
  end
end
