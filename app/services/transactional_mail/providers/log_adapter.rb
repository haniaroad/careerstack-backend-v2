# frozen_string_literal: true

module TransactionalMail
  module Providers
    class LogAdapter
      def deliver(to:, subject:, html:, text:, reply_to: nil)
        Rails.logger.info(
          {
            event: "transactional_mail_log",
            to_digest: Digest::SHA256.hexdigest(to.to_s.downcase),
            subject: subject,
            reply_to: reply_to,
            text_present: text.present?,
            html_present: html.present?
          }.to_json
        )
        { status: "logged" }
      end
    end
  end
end
