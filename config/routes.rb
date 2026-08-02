# frozen_string_literal: true

Rails.application.routes.draw do
  get "health", to: "health#show"
  get "ready", to: "readiness#show"
  get "up", to: "health#show"

  namespace :api do
    namespace :v1 do
      get "session", to: "sessions#show"
      post "onboarding/independent", to: "onboarding#independent"
      post "onboarding/organization_invited", to: "onboarding#organization_invited"
      get "workspaces", to: "workspaces#index"
      post "workspaces/switch", to: "workspaces#switch"
      post "organizations", to: "organizations#create"
      post "invitations", to: "invitations#create"
      get "invitations/:token", to: "invitations#show"
      post "invitations/:token/accept", to: "invitations#accept"
      get "taxonomies", to: "taxonomies#index"
      patch "age_visibility", to: "age_visibilities#update"
    end
  end

  match "*unmatched", to: "errors#not_found", via: :all
end
