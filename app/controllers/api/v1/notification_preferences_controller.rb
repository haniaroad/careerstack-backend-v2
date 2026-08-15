# frozen_string_literal: true

module Api
  module V1
    class NotificationPreferencesController < BaseController
      def show
        render json: { preferences: NotificationPreferenceSerializer.list(current_user) }
      end

      def update
        items = Array(params[:preferences])
        raise DomainError.new("preferences is required") if items.empty?

        NotificationPreference.ensure_defaults!(current_user)
        items.each do |item|
          item = item.to_unsafe_h if item.respond_to?(:to_unsafe_h)
          item = item.to_h.with_indifferent_access
          category = item[:id].to_s
          meta = Notifications::Catalog::CATEGORIES[category]
          raise DomainError.new("Unknown preference category") if meta.nil?

          preference = current_user.notification_preferences.find_by!(category: category)
          if !meta[:can_disable] && item.key?(:email_enabled) && !ActiveModel::Type::Boolean.new.cast(item[:email_enabled])
            raise DomainError.new("Mandatory email categories cannot be disabled")
          end

          attrs = {}
          attrs[:email_enabled] = ActiveModel::Type::Boolean.new.cast(item[:email_enabled]) if item.key?(:email_enabled)
          if item.key?(:digest_cadence)
            cadence = item[:digest_cadence].to_s
            unless NotificationPreference::CADENCES.include?(cadence)
              raise DomainError.new("digest_cadence is invalid")
            end
            attrs[:digest_cadence] = cadence
            attrs[:email_enabled] = false if cadence == "off"
          end
          preference.update!(attrs) if attrs.present?
        end

        render json: { preferences: NotificationPreferenceSerializer.list(current_user.reload) }
      end
    end
  end
end
