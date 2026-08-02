# frozen_string_literal: true

# Derives the age status the rest of the application is allowed to see.
#
# The adult boundary is the start of the 18th birthday in the organization's
# timezone (D-6), so the "as of" instant is always converted to a local date
# before any comparison.
class AgeStatusCalculator
  ADULT_AGE = 18
  MINIMUM_REGISTRATION_AGE = 13

  ADULT = "adult"
  MINOR = "minor"
  UNKNOWN = "unknown"

  class << self
    def call(date_of_birth:, timezone: "UTC", as_of: Time.current)
      new(date_of_birth: date_of_birth, timezone: timezone, as_of: as_of).call
    end

    def age_in_years(date_of_birth:, timezone: "UTC", as_of: Time.current)
      new(date_of_birth: date_of_birth, timezone: timezone, as_of: as_of).age_in_years
    end

    # A-41 baseline: under-13 registration is refused outright rather than
    # stored as a restricted minor.
    def below_minimum_registration_age?(date_of_birth:, timezone: "UTC", as_of: Time.current)
      age = age_in_years(date_of_birth: date_of_birth, timezone: timezone, as_of: as_of)
      return false if age.nil?

      age < MINIMUM_REGISTRATION_AGE
    end
  end

  def initialize(date_of_birth:, timezone: "UTC", as_of: Time.current)
    @date_of_birth = date_of_birth
    @timezone = timezone.presence || "UTC"
    @as_of = as_of
  end

  # Only a missing date of birth yields "unknown"; a known date always resolves
  # to adult or minor.
  def call
    age = age_in_years
    return UNKNOWN if age.nil?

    age >= ADULT_AGE ? ADULT : MINOR
  end

  def age_in_years
    return nil if @date_of_birth.blank?

    local_date = @as_of.in_time_zone(@timezone).to_date
    years = local_date.year - @date_of_birth.year
    birthday_passed?(local_date) ? years : years - 1
  end

  private

  def birthday_passed?(local_date)
    return true if local_date.month > @date_of_birth.month
    return false if local_date.month < @date_of_birth.month

    local_date.day >= @date_of_birth.day
  end
end
