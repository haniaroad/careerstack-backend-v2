locals {
  name_prefix = "careerstack-staging"
  labels = {
    app         = "careerstack"
    environment = "staging"
    managed_by  = "opentofu"
  }
}

resource "google_artifact_registry_repository" "api" {
  location      = var.region
  repository_id = "careerstack-api"
  description   = "CareerStack API container images (staging)"
  format        = "DOCKER"
  labels        = local.labels
}

resource "google_service_account" "runtime" {
  account_id   = "careerstack-api-runtime"
  display_name = "CareerStack API runtime (staging)"
}

resource "google_service_account" "deploy" {
  account_id   = "careerstack-github-deploy"
  display_name = "CareerStack GitHub Actions deploy (staging)"
}

resource "google_project_iam_member" "runtime_sql_client" {
  project = var.project_id
  role    = "roles/cloudsql.client"
  member  = "serviceAccount:${google_service_account.runtime.email}"
}

resource "google_project_iam_member" "runtime_secret_accessor" {
  project = var.project_id
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${google_service_account.runtime.email}"
}

resource "google_project_iam_member" "runtime_storage" {
  project = var.project_id
  role    = "roles/storage.objectAdmin"
  member  = "serviceAccount:${google_service_account.runtime.email}"
}

resource "google_project_iam_member" "deploy_run_admin" {
  project = var.project_id
  role    = "roles/run.admin"
  member  = "serviceAccount:${google_service_account.deploy.email}"
}

resource "google_project_iam_member" "deploy_ar_writer" {
  project = var.project_id
  role    = "roles/artifactregistry.writer"
  member  = "serviceAccount:${google_service_account.deploy.email}"
}

resource "google_project_iam_member" "deploy_sa_user" {
  project = var.project_id
  role    = "roles/iam.serviceAccountUser"
  member  = "serviceAccount:${google_service_account.deploy.email}"
}

resource "google_project_iam_member" "deploy_sql_client" {
  project = var.project_id
  role    = "roles/cloudsql.client"
  member  = "serviceAccount:${google_service_account.deploy.email}"
}

resource "google_sql_database_instance" "primary" {
  name             = "${local.name_prefix}-pg"
  database_version = "POSTGRES_16"
  region           = var.region

  settings {
    tier              = var.db_tier
    edition           = "ENTERPRISE"
    availability_type = "ZONAL"
    disk_size         = 10
    disk_type         = "PD_HDD"

    ip_configuration {
      ipv4_enabled = true
    }

    backup_configuration {
      enabled = false
    }

    user_labels = local.labels
  }

  deletion_protection = false
}

resource "google_sql_database" "app" {
  name     = "careerstack"
  instance = google_sql_database_instance.primary.name
}

resource "google_sql_database" "queue" {
  name     = "careerstack_queue"
  instance = google_sql_database_instance.primary.name
}

resource "random_password" "db" {
  length  = 32
  special = false
}

resource "google_sql_user" "app" {
  name     = "careerstack"
  instance = google_sql_database_instance.primary.name
  password = random_password.db.result
}

resource "google_storage_bucket" "app" {
  name                        = "${var.project_id}-app-private"
  location                    = var.region
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  force_destroy               = true

  labels = local.labels
}

resource "google_secret_manager_secret" "database_url" {
  secret_id = "database-url"
  replication {
    auto {}
  }
  labels = local.labels
}

resource "google_secret_manager_secret" "queue_database_url" {
  secret_id = "queue-database-url"
  replication {
    auto {}
  }
  labels = local.labels
}

resource "google_secret_manager_secret" "secret_key_base" {
  secret_id = "secret-key-base"
  replication {
    auto {}
  }
  labels = local.labels
}

resource "google_secret_manager_secret" "sentry_dsn" {
  secret_id = "sentry-dsn"
  replication {
    auto {}
  }
  labels = local.labels
}

resource "google_secret_manager_secret_version" "database_url" {
  secret      = google_secret_manager_secret.database_url.id
  secret_data = "postgres://${google_sql_user.app.name}:${random_password.db.result}@/${google_sql_database.app.name}?host=/cloudsql/${google_sql_database_instance.primary.connection_name}"
}

resource "google_secret_manager_secret_version" "queue_database_url" {
  secret      = google_secret_manager_secret.queue_database_url.id
  secret_data = "postgres://${google_sql_user.app.name}:${random_password.db.result}@/${google_sql_database.queue.name}?host=/cloudsql/${google_sql_database_instance.primary.connection_name}"
}

resource "random_password" "secret_key_base" {
  length  = 64
  special = false
}

resource "google_secret_manager_secret_version" "secret_key_base" {
  secret      = google_secret_manager_secret.secret_key_base.id
  secret_data = random_password.secret_key_base.result
}

resource "google_secret_manager_secret_version" "sentry_dsn_placeholder" {
  secret      = google_secret_manager_secret.sentry_dsn.id
  secret_data = "pending"
}

resource "google_cloud_run_v2_service" "api" {
  name     = "careerstack-api"
  location = var.region
  ingress  = "INGRESS_TRAFFIC_ALL"

  template {
    service_account = google_service_account.runtime.email

    scaling {
      min_instance_count = 0
      max_instance_count = 2
    }

    volumes {
      name = "cloudsql"
      cloud_sql_instance {
        instances = [google_sql_database_instance.primary.connection_name]
      }
    }

    containers {
      image = var.image

      # Placeholder hello image listens on 8080; first CI deploy replaces image + port 3000.
      ports {
        container_port = 8080
      }

      env {
        name  = "RAILS_ENV"
        value = "production"
      }

      env {
        name  = "CORS_ORIGINS"
        value = "https://staging.careerstack.co,http://localhost:5173"
      }

      env {
        name = "DATABASE_URL"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.database_url.secret_id
            version = "latest"
          }
        }
      }

      env {
        name = "QUEUE_DATABASE_URL"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.queue_database_url.secret_id
            version = "latest"
          }
        }
      }

      env {
        name = "SECRET_KEY_BASE"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.secret_key_base.secret_id
            version = "latest"
          }
        }
      }

      volume_mounts {
        name       = "cloudsql"
        mount_path = "/cloudsql"
      }
    }
  }

  labels = local.labels

  depends_on = [
    google_secret_manager_secret_version.database_url,
    google_secret_manager_secret_version.queue_database_url,
    google_secret_manager_secret_version.secret_key_base,
  ]
}

# NOTE: Organization policy currently rejects member "allUsers" on Cloud Run.
# Public invoker binding must be granted after an org-policy exception (console
# or a follow-up change). Until then, callers need an identity with roles/run.invoker.

resource "google_iam_workload_identity_pool" "github" {
  workload_identity_pool_id = "github-actions"
  display_name              = "GitHub Actions"
}

resource "google_iam_workload_identity_pool_provider" "github" {
  workload_identity_pool_id          = google_iam_workload_identity_pool.github.workload_identity_pool_id
  workload_identity_pool_provider_id = "github"
  display_name                       = "GitHub OIDC"

  attribute_mapping = {
    "google.subject"       = "assertion.sub"
    "attribute.actor"      = "assertion.actor"
    "attribute.repository" = "assertion.repository"
    "attribute.ref"        = "assertion.ref"
  }

  attribute_condition = "assertion.repository_owner == '${var.github_org}'"

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}

resource "google_service_account_iam_member" "wif_backend" {
  service_account_id = google_service_account.deploy.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/attribute.repository/${var.github_org}/${var.github_backend_repo}"
}

resource "google_service_account_iam_member" "wif_frontend" {
  service_account_id = google_service_account.deploy.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/attribute.repository/${var.github_org}/${var.github_frontend_repo}"
}

resource "google_monitoring_uptime_check_config" "api_health" {
  display_name = "careerstack-api-health"
  timeout      = "10s"
  period       = "60s"

  http_check {
    path         = "/health"
    port         = "443"
    use_ssl      = true
    validate_ssl = true
  }

  monitored_resource {
    type = "uptime_url"
    labels = {
      project_id = var.project_id
      host       = trimprefix(google_cloud_run_v2_service.api.uri, "https://")
    }
  }
}

resource "google_billing_budget" "staging" {
  count = var.billing_account == "" ? 0 : 1

  billing_account = var.billing_account
  display_name    = "careerstack-staging-monthly"

  budget_filter {
    projects = ["projects/${var.project_number}"]
  }

  amount {
    specified_amount {
      currency_code = "USD"
      units         = tostring(var.budget_amount_usd)
    }
  }

  threshold_rules {
    threshold_percent = 0.5
  }

  threshold_rules {
    threshold_percent = 0.9
  }

  threshold_rules {
    threshold_percent = 1.0
  }
}
