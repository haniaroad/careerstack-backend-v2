# frozen_string_literal: true

module Api
  module V1
    module Public
      class ProfilesController < BaseController
        skip_before_action :require_authentication

        def show
          profile = Profile.find_by(slug: params[:slug].to_s.downcase)
          raise DomainError.new("Profile not found", code: "not_found", status: :not_found) if profile.nil?

          target = profile.user
          unless Profiles::Visibility.public_adult?(target)
            raise DomainError.new("Profile not found", code: "not_found", status: :not_found)
          end

          render json: {
            profile: ProfileSerializer.public_for(target, viewer: nil),
            canonical_path: "/profile/#{profile.slug}",
            indexable: true
          }
        end
      end
    end
  end
end
