# frozen_string_literal: true

module Api
  module V1
    class OrganizationMembershipsController < BaseController
      def index
        access = Organizations::Access.staff!(user: current_user, organization_id: params[:organization_id])
        memberships = access.organization.organization_memberships.active.includes(:user, :enrolled_programs, user: :profile)
        memberships = memberships.where(role: params[:role]) if params[:role].present?
        if params[:q].present?
          query = "%#{ActiveRecord::Base.sanitize_sql_like(params[:q].to_s.strip)}%"
          memberships = memberships.joins(:user).left_joins(user: :profile).where(
            "users.email ILIKE :q OR profiles.display_name ILIKE :q",
            q: query
          )
        end
        if params[:program_id].present?
          memberships = memberships.joins(:program_enrollments).where(program_enrollments: { program_id: params[:program_id] })
        end

        render json: { memberships: memberships.order(:created_at).uniq.map { |m| OrganizationMembershipSerializer.call(m) } }
      end

      def update
        target = OrganizationMembership.find(params[:id])
        access = Organizations::Access.staff!(user: current_user, organization_id: target.organization_id)
        updated = Memberships::Update.call(
          actor_membership: access.membership,
          target: target,
          params: { role: params[:role], program_ids: params[:program_ids] }.compact
        )
        render json: { membership: OrganizationMembershipSerializer.call(updated) }
      end

      def remove
        target = OrganizationMembership.find(params[:id])
        Organizations::Access.admin!(user: current_user, organization_id: target.organization_id)
        removed = Memberships::Remove.call(actor: current_user, target: target, reason: params[:reason])
        render json: { membership: OrganizationMembershipSerializer.call(removed) }
      end
    end
  end
end
