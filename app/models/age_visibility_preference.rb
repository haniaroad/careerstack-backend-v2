# frozen_string_literal: true

# Tracks whether an org-derived user has opted into public identity after aging
# up. Profiles stay restricted until public_identity_confirmed is true, and the
# user can reverse that choice at any time.
class AgeVisibilityPreference < ApplicationRecord
  belongs_to :user

  validates :user_id, uniqueness: true

  def confirm_public_identity!
    update!(
      public_identity_confirmed: true,
      visibility_review_required: false,
      confirmed_at: Time.current
    )
  end

  def reverse_public_identity!
    update!(public_identity_confirmed: false, confirmed_at: nil)
  end

  def require_visibility_review!
    update!(visibility_review_required: true, public_identity_confirmed: false, confirmed_at: nil)
  end
end
