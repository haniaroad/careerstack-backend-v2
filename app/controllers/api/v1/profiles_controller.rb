# frozen_string_literal: true

module Api
  module V1
    class ProfilesController < BaseController
      def me
        Profiles::AssignSlug.call(profile: current_user.profile) if current_user.profile&.slug.blank?
        render json: { profile: ProfileSerializer.own(current_user.reload) }
      end

      def update_me
        Profiles::Update.call(user: current_user, params: profile_params)
        render json: { profile: ProfileSerializer.own(current_user.reload) }
      end

      def visibility
        Profiles::ConfirmVisibility.call(user: current_user, decision: params.require(:decision))
        render json: {
          profile: ProfileSerializer.own(current_user.reload),
          session: SessionSerializer.call(current_user)
        }
      end

      def show
        profile = Profile.find_by(slug: params[:slug].to_s.downcase)
        raise DomainError.new("Profile not found", code: "not_found", status: :not_found) if profile.nil?

        target = profile.user
        if target.id == current_user.id
          Profiles::AssignSlug.call(profile: profile) if profile.slug.blank?
          return render json: { profile: ProfileSerializer.own(current_user.reload) }
        end

        unless Profiles::Visibility.public_adult?(target)
          raise DomainError.new("Profile not found", code: "not_found", status: :not_found)
        end

        render json: { profile: ProfileSerializer.public_for(target, viewer: current_user) }
      end

      private

      def profile_params
        params.permit(
          :display_name, :country, :state_region, :career_goal,
          :current_role_term_id, :current_role_other, :experience_level,
          :target_role_term_id, :target_role_other,
          :bio, :image_url, :github_url, :linkedin_url, :portfolio_url,
          interests: []
        )
      end
    end
  end
end
