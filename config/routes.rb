# frozen_string_literal: true

Rails.application.routes.draw do
  get "health", to: "health#show"
  get "ready", to: "readiness#show"
  get "up", to: "health#show"

  match "*unmatched", to: "errors#not_found", via: :all
end
