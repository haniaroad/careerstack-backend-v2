# frozen_string_literal: true

namespace :platform_admin do
  desc "Activate a platform admin by email (claim must be set in Firebase; stub mode records the staff row only)"
  task :provision, [ :email ] => :environment do |_task, args|
    email = args[:email].presence || abort("Usage: rails platform_admin:provision[email]")
    staff = PlatformAdmin::Provision.call(email: email, active: true)
    puts "Staff record #{staff.id} active for #{email}. Sign in again after the Firebase claim is set."
  end

  desc "Deactivate a platform admin by email"
  task :deactivate, [ :email ] => :environment do |_task, args|
    email = args[:email].presence || abort("Usage: rails platform_admin:deactivate[email]")
    PlatformAdmin::Provision.call(email: email, active: false)
    puts "Staff record deactivated for #{email}."
  end

  desc "Anonymize accounts whose 30-day deletion recovery window has elapsed"
  task anonymize: :environment do
    count = PlatformAdmin::AnonymizeDue.call
    puts "Anonymized #{count} accounts."
  end
end
