# frozen_string_literal: true

class AddProfilePhotoUploadWindow < ActiveRecord::Migration[8.1]
  def up
    add_column :profiles, :photo_upload_window_started_at, :datetime
    add_column :profiles, :photo_upload_attempts, :integer, null: false, default: 0
    Profiles::ClearLegacyImageUrls.call
  end

  def down
    remove_column :profiles, :photo_upload_attempts
    remove_column :profiles, :photo_upload_window_started_at
  end
end
