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
      get "credits", to: "credits#show"
      get "credits/history", to: "credits#history"
      get "projects", to: "projects#index"
      post "projects", to: "projects#create"
      get "projects/:id", to: "projects#show"
      patch "projects/:id", to: "projects#update"
      delete "projects/:id", to: "projects#destroy"
      post "projects/:id/confirm", to: "projects#confirm"
      post "projects/:id/cancel", to: "projects#cancel"
      get "tasks", to: "tasks#index"
      get "tasks/:id", to: "tasks#show"
      post "tasks/:task_id/submissions", to: "task_submissions#create"
      post "tasks/:task_id/ai_reviews", to: "ai_reviews#create"
      get "ai/reviews/:id", to: "ai_reviews#show"
      post "ai/reviews/:id/reports", to: "ai_review_reports#create"
      post "direct_uploads", to: "direct_uploads#create"
      put "blob_uploads/:signed_id", to: "direct_uploads#upload", as: :blob_upload
      post "ai/project_generations", to: "project_generations#create"
      get "ai/project_generations/:id", to: "project_generations#show"
      post "ai/project_generations/:id/accept", to: "project_generations#accept"
      post "billing/checkout_sessions", to: "billing/checkout_sessions#create"
      get "billing/purchases", to: "billing/purchases#index"
      get "billing/purchases/:id", to: "billing/purchases#show"
      post "billing/refund_requests", to: "billing/refund_requests#create"
      post "stripe/webhooks", to: "stripe_webhooks#create"
    end
  end

  match "*unmatched", to: "errors#not_found", via: :all
end
