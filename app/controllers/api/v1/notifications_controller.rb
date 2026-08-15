# frozen_string_literal: true

module Api
  module V1
    class NotificationsController < BaseController
      def index
        scope = Notification.in_app.for_user(current_user).order(Arel.sql("read_at IS NOT NULL"), created_at: :desc)
        scope = scope.unread if ActiveModel::Type::Boolean.new.cast(params[:unread])
        limit = [ [ Integer(params[:limit] || 30, exception: false) || 30, 1 ].max, 100 ].min
        notifications = scope.limit(limit)
        render json: { notifications: NotificationSerializer.list(notifications) }
      end

      def unread_count
        render json: { unread_count: Notification.in_app.for_user(current_user).unread.count }
      end

      def read
        notification = Notification.in_app.for_user(current_user).find_by(id: params[:id])
        raise DomainError.new("Notification not found", code: "not_found", status: :not_found) if notification.nil?

        notification.mark_read!
        render json: { notification: NotificationSerializer.call(notification) }
      end

      def read_all
        Notification.in_app.for_user(current_user).unread.update_all(read_at: Time.current)
        render json: { unread_count: 0 }
      end
    end
  end
end
