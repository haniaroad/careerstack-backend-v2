# frozen_string_literal: true

require "rails_helper"

RSpec.describe TransactionalMail::Renderer do
  let(:heading) { "You've been invited to Bridgepoint Collective" }
  let(:body) { "Marisol Vega invited you to join Bridgepoint Collective on CareerStack." }
  let(:cta) { "Accept invitation" }
  let(:notification) do
    instance_double(
      Notification,
      tier: "configurable",
      payload: {
        "heading" => heading,
        "body" => body,
        "cta" => cta,
        "path" => "/invite/example"
      }
    )
  end

  subject(:mail) { described_class.call(notification: notification) }

  it "renders the approved palette and keeps the fixture copy in html and text" do
    html = mail[:html]
    text = mail[:text]

    expect(html).to include("background:#f3efe7")
    expect(html).to include("background:#fbf8f3")
    expect(html).to include("color:#1c1917")
    expect(html).to include("color:#57534e")
    expect(html).to include("border:1px solid #dcd3c4")
    expect(html).to include("background:#9a3412")
    expect(html).to include("color:#fbf8f3")
    expect(html).not_to include("#4F46E5")
    expect(html).not_to include("#0B0B0D")
    expect(html).not_to include("#FAFAF9")
    expect(html).not_to include("#E2E8F0")
    expect(html).not_to include("#FFFFFF")

    expect(html).to include("You&#39;ve been invited to Bridgepoint Collective")
    expect(html).to include(body)
    expect(html).to include(cta)
    expect(text).to include(heading)
    expect(text).to include(body)
    expect(text).to include("#{cta}: http://localhost:5173/invite/example")
  end
end
