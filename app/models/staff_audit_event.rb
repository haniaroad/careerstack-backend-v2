# frozen_string_literal: true

class StaffAuditEvent < ApplicationRecord
  belongs_to :actor, class_name: "User"

  validates :action, :target_type, :target_id, presence: true

  def update(*)
    raise DomainError.new("Audit records cannot be changed", code: "forbidden", status: :forbidden)
  end

  def update!(*)
    update
  end

  def destroy
    raise DomainError.new("Audit records cannot be deleted", code: "forbidden", status: :forbidden)
  end

  def destroy!(*)
    destroy
  end
end
