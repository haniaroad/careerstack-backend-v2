variable "project_id" {
  type        = string
  description = "GCP project id for staging"
  default     = "careerstack-staging"
}

variable "project_number" {
  type        = string
  description = "GCP project number for staging"
  default     = "11197815680"
}

variable "region" {
  type        = string
  description = "Primary region"
  default     = "us-east5"
}

variable "github_org" {
  type        = string
  description = "GitHub organization or user that owns the deploy repos"
  default     = "haniaroad"
}

variable "github_backend_repo" {
  type        = string
  default     = "careerstack-backend-v2"
}

variable "github_frontend_repo" {
  type        = string
  default     = "careerstack-frontend-v2"
}

variable "billing_account" {
  type        = string
  description = "Billing account id for budget alerts (XXXXXX-XXXXXX-XXXXXX)"
  default     = ""
}

variable "budget_amount_usd" {
  type        = number
  description = "Monthly budget alert amount in USD for staging"
  default     = 50
}

variable "db_tier" {
  type        = string
  description = "Cloud SQL machine tier"
  default     = "db-f1-micro"
}

variable "image" {
  type        = string
  description = "Initial Cloud Run container image (placeholder until first CI push)"
  default     = "us-docker.pkg.dev/cloudrun/container/hello"
}

variable "firebase_project_id" {
  type        = string
  description = "Firebase project ID used to verify ID tokens in production Cloud Run"
  default     = "careerstack-staging"
}

variable "allow_unauthenticated_invoker" {
  type        = bool
  description = <<-EOT
    When true, grants roles/run.invoker to allUsers so the Netlify SPA can call the API
    with Firebase Bearer tokens. Requires an org-policy exception for domain-restricted
    sharing (allUsers is blocked by default on careerstack-staging).
  EOT
  default     = false
}
