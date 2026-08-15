# frozen_string_literal: true

require "net/http"
require "uri"

module TransactionalMail
  module Providers
    class MailgunAdapter
      def deliver(to:, subject:, html:, text:, reply_to: nil)
        api_key = ENV.fetch("MAILGUN_API_KEY")
        domain = ENV.fetch("MAILGUN_DOMAIN")
        from = ENV.fetch("MAILGUN_FROM", "CareerStack <notifications@#{domain}>")

        uri = URI("https://api.mailgun.net/v3/#{domain}/messages")
        request = Net::HTTP::Post.new(uri)
        request.basic_auth("api", api_key)
        form = {
          "from" => from,
          "to" => to,
          "subject" => subject,
          "text" => text,
          "html" => html
        }
        form["h:Reply-To"] = reply_to if reply_to.present?
        request.set_form_data(form)

        response = Net::HTTP.start(uri.host, uri.port, use_ssl: true) do |http|
          http.request(request)
        end
        unless response.is_a?(Net::HTTPSuccess)
          raise "Mailgun delivery failed (#{response.code})"
        end

        { status: "sent", provider_id: response.body }
      end
    end
  end
end
