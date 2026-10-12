# frozen_string_literal: true

class TaskSubmissionSerializer
  # Long enough for a review session. The service URL minted by the redirect stays short-lived.
  REVIEW_URL_TTL = 12.hours

  def self.call(submission, host: nil)
    new(submission, host: host).as_json
  end

  def initialize(submission, host: nil)
    @submission = submission
    @host = host
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
      signed_id: blob.signed_id(expires_in: REVIEW_URL_TTL),
      url: blob_url(attachment)
    }
  end

  def blob_url(attachment)
    Rails.application.routes.url_helpers.rails_blob_url(
      attachment,
      disposition: "inline",
      expires_in: REVIEW_URL_TTL,
      host: @host.presence || "www.example.com"
    )
  end
end
