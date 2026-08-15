# frozen_string_literal: true

module TransactionalMail
  class Renderer
    INK = "#0B0B0D"
    CANVAS = "#FAFAF9"
    SURFACE = "#FFFFFF"
    BODY = "#475569"
    META = "#64748B"
    INDIGO = "#4F46E5"

    def self.call(notification:, items: nil)
      new(notification: notification, items: items).call
    end

    def initialize(notification:, items:)
      @notification = notification
      @items = items
    end

    def call
      payload = @notification.payload || {}
      heading = payload["heading"].presence || payload["title"].presence || "CareerStack update"
      body = body_text(payload)
      cta = payload["cta"].presence || "Open CareerStack"
      path = payload["path"].presence || "/"
      origin = ENV.fetch("APP_ORIGIN", "http://localhost:5173")
      url = "#{origin}#{path}"
      mandatory = @notification.tier == "mandatory"
      preheader = body.to_s.truncate(90)

      {
        subject: subject_for(heading),
        html: html(preheader: preheader, heading: heading, body: body, cta: cta, url: url, mandatory: mandatory),
        text: text(heading: heading, body: body, cta: cta, url: url, mandatory: mandatory)
      }
    end

    private

    def body_text(payload)
      if @items.present? && @items.size > 1
        lines = @items.map { |item| "- #{item.payload['title'].presence || item.payload['heading']}" }
        "#{payload['body']}\n\n#{lines.join("\n")}"
      else
        payload["body"].to_s
      end
    end

    def subject_for(heading)
      heading.to_s.truncate(45)
    end

    def html(preheader:, heading:, body:, cta:, url:, mandatory:)
      footer = if mandatory
        "You received this because it is a required CareerStack account notice."
      else
        "Change email frequency in Settings: #{ENV.fetch('APP_ORIGIN', 'http://localhost:5173')}/profile?tab=settings"
      end

      <<~HTML
        <!DOCTYPE html>
        <html lang="en">
        <head><meta charset="utf-8"><title>#{escape(heading)}</title>
        <meta name="color-scheme" content="light dark"><meta name="supported-color-schemes" content="light dark"></head>
        <body style="margin:0;padding:0;background:#{CANVAS};">
        <div style="display:none;max-height:0;overflow:hidden;">#{escape(preheader)}</div>
        <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#{CANVAS};">
          <tr><td align="center" style="padding:24px;">
            <table role="presentation" width="600" cellpadding="0" cellspacing="0" style="max-width:600px;background:#{SURFACE};border:1px solid #E2E8F0;">
              <tr><td style="padding:24px;font-family:Arial,Helvetica,sans-serif;color:#{INK};font-size:24px;font-weight:700;">CareerStack</td></tr>
              <tr><td style="padding:0 24px 16px;font-family:Arial,Helvetica,sans-serif;color:#{INK};font-size:20px;">#{escape(heading)}</td></tr>
              <tr><td style="padding:0 24px 24px;font-family:Arial,Helvetica,sans-serif;color:#{BODY};font-size:16px;line-height:1.5;">#{escape(body).gsub("\n", "<br>")}</td></tr>
              <tr><td style="padding:0 24px 24px;">
                <a href="#{escape(url)}" style="display:inline-block;background:#{INK};color:#FFFFFF;text-decoration:none;padding:12px 24px;border-radius:6px;font-family:Arial,Helvetica,sans-serif;font-size:16px;">#{escape(cta)}</a>
              </td></tr>
              <tr><td style="padding:0 24px 24px;font-family:Arial,Helvetica,sans-serif;color:#{BODY};font-size:14px;">— The CareerStack team</td></tr>
              <tr><td style="padding:16px 24px;font-family:Arial,Helvetica,sans-serif;color:#{META};font-size:12px;">#{escape(footer)}<br>© CareerStack</td></tr>
            </table>
          </td></tr>
        </table>
        </body></html>
      HTML
    end

    def text(heading:, body:, cta:, url:, mandatory:)
      footer = if mandatory
        "You received this because it is a required CareerStack account notice."
      else
        "Change email frequency: #{ENV.fetch('APP_ORIGIN', 'http://localhost:5173')}/profile?tab=settings"
      end
      [ heading, "", body, "", "#{cta}: #{url}", "", footer, "© CareerStack" ].join("\n")
    end

    def escape(value)
      ERB::Util.html_escape(value.to_s)
    end
  end
end
