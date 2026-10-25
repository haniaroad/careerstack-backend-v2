# frozen_string_literal: true

class AllowNullFirebaseUidOnUsers < ActiveRecord::Migration[8.1]
  def change
    change_column_null :users, :firebase_uid, true
  end
end
