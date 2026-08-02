# frozen_string_literal: true

require "rails_helper"

RSpec.describe FirebaseTokenVerifier do
  describe "stub mode" do
    it "resolves a well-formed stub token to a normalized identity" do
      identity = described_class.verify!("Bearer test:uid-1:Alex@Example.com")

      expect(identity.firebase_uid).to eq("uid-1")
      expect(identity.email).to eq("alex@example.com")
    end

    it "rejects a blank header" do
      expect { described_class.verify!(nil) }.to raise_error(described_class::VerificationError)
      expect { described_class.verify!("   ") }.to raise_error(described_class::VerificationError)
    end

    it "rejects a credential without the Bearer scheme" do
      expect { described_class.verify!("test:uid-1:alex@example.com") }
        .to raise_error(described_class::VerificationError)
    end

    it "rejects a token that is not in stub form" do
      expect { described_class.verify!("Bearer eyJhbGciOiJSUzI1NiJ9.payload.signature") }
        .to raise_error(described_class::VerificationError, /Invalid stub token/)
    end

    it "rejects a stub token missing the email segment" do
      expect { described_class.verify!("Bearer test:uid-1") }
        .to raise_error(described_class::VerificationError, /test:<firebase_uid>:<email>/)
    end

    it "rejects a stub token with a blank uid" do
      expect { described_class.verify!("Bearer test::alex@example.com") }
        .to raise_error(described_class::VerificationError)
    end
  end

  describe ".stub_mode?" do
    it "is enabled by default in the test environment" do
      expect(described_class).to be_stub_mode
    end

    it "can be disabled explicitly" do
      with_env("FIREBASE_AUTH_STUB" => "false") do
        expect(described_class).not_to be_stub_mode
      end
    end

    it "is never enabled in production, even when requested" do
      allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("production"))

      with_env("FIREBASE_AUTH_STUB" => "true") do
        expect(described_class).not_to be_stub_mode
      end
    end
  end

  describe "real verification mode" do
    around do |example|
      with_env("FIREBASE_AUTH_STUB" => "false") { example.run }
    end

    it "refuses to verify when no Firebase project is configured" do
      with_env("FIREBASE_PROJECT_ID" => nil) do
        expect { described_class.verify!("Bearer some.jwt.token") }
          .to raise_error(described_class::VerificationError, /FIREBASE_PROJECT_ID/)
      end
    end

    it "rejects a token that is not a decodable JWT" do
      allow(described_class).to receive(:jwks).and_return({ "keys" => [] })

      with_env("FIREBASE_PROJECT_ID" => "careerstack-staging") do
        expect { described_class.verify!("Bearer not-a-jwt") }
          .to raise_error(described_class::VerificationError, /Token verification failed/)
      end
    end

    it "rejects a token signed by a key outside Google's JWKS" do
      allow(described_class).to receive(:jwks).and_return({ "keys" => [] })
      token = JWT.encode(
        {
          sub: "uid-1",
          email: "alex@example.com",
          email_verified: true,
          iss: "https://securetoken.google.com/careerstack-staging",
          aud: "careerstack-staging",
          exp: 1.hour.from_now.to_i,
          iat: Time.current.to_i
        },
        OpenSSL::PKey::RSA.generate(2048),
        "RS256",
        kid: "not-a-google-kid"
      )

      with_env("FIREBASE_PROJECT_ID" => "careerstack-staging") do
        expect { described_class.verify!("Bearer #{token}") }
          .to raise_error(described_class::VerificationError)
      end
    end

    it "surfaces a verification error when Google's signing keys cannot be fetched" do
      described_class.reset_jwks_cache!
      allow(Net::HTTP).to receive(:get_response).and_return(Net::HTTPServerError.new("1.1", "500", "error"))

      expect { described_class.jwks }.to raise_error(described_class::VerificationError, /signing keys/)
    ensure
      described_class.reset_jwks_cache!
    end
  end
end
