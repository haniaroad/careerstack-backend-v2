# frozen_string_literal: true

module TransactionalMail
  module Provider
    class << self
      def deliver(to:, subject:, html:, text:, reply_to: nil)
        adapter.deliver(to: to, subject: subject, html: html, text: text, reply_to: reply_to)
      end

      def adapter
        @adapter || default_adapter
      end

      def stub!(provider)
        @adapter = provider
      end

      def unstub!
        @adapter = nil
      end

      private

      def default_adapter
        case ENV.fetch("MAIL_ADAPTER", "log")
        when "mailgun"
          Providers::MailgunAdapter.new
        else
          Providers::LogAdapter.new
        end
      end
    end
  end
end
