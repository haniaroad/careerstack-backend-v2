# frozen_string_literal: true

module Api
  module V1
    class InboxItemsController < BaseController
      def index
        workspace = require_workspace!
        items = Inbox::ListItems.call(
          workspace: workspace,
          user: current_user,
          category: params[:category],
          limit: (params[:limit].presence || 50).to_i
        )
        render json: {
          items: items.map { |item| InboxItemSerializer.call(item) }
        }
      end

      def show
        workspace = require_workspace!
        category, related_id = parse_item_id!(params[:id])
        items = Inbox::ListItems.call(workspace: workspace, user: current_user, category: category, limit: 100)
        item = items.find { |candidate| candidate.related_id.to_s == related_id || candidate.id == params[:id] }
        raise ActiveRecord::RecordNotFound if item.nil?

        render json: { item: InboxItemSerializer.call(item) }
      end

      private

      def require_workspace!
        workspace = current_user.resolved_active_workspace
        raise DomainError.new("No active workspace", code: "no_workspace") if workspace.nil?

        workspace
      end

      def parse_item_id!(raw)
        category, related_id = raw.to_s.split(":", 2)
        unless Inbox::ListItems::CATEGORIES.include?(category) && related_id.present?
          raise DomainError.new("Invalid inbox item id", code: "validation_error")
        end

        [ category, related_id ]
      end
    end
  end
end
