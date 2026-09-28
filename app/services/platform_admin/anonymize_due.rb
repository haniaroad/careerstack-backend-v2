# frozen_string_literal: true

module PlatformAdmin
  class AnonymizeDue
    WINDOW = 30.days

    def self.call(now: Time.current)
      due = User.where(anonymized_at: nil, deletion_cancelled_at: nil)
                .where.not(deletion_requested_at: nil)
                .where(deletion_requested_at: ..(now - WINDOW))
      count = 0
      due.find_each do |user|
        anonymize!(user)
        count += 1
      end
      count
    end

    def self.anonymize!(user)
      user.profile&.update!(
        display_name: "Deleted user",
        bio: nil,
        image_url: nil,
        github_url: nil,
        linkedin_url: nil,
        portfolio_url: nil,
        date_of_birth: nil,
        interests: []
      )
      user.update!(
        email: "deleted-#{user.id}@careerstack.invalid",
        firebase_uid: "deleted-#{user.id}",
        anonymized_at: Time.current
      )
    end
  end
end
