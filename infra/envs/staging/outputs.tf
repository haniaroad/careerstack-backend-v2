output "cloud_run_uri" {
  description = "Staging Cloud Run service URL"
  value       = google_cloud_run_v2_service.api.uri
}

output "artifact_registry_repository" {
  value = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.api.repository_id}"
}

output "cloud_sql_connection_name" {
  value = google_sql_database_instance.primary.connection_name
}

output "runtime_service_account" {
  value = google_service_account.runtime.email
}

output "deploy_service_account" {
  value = google_service_account.deploy.email
}

output "workload_identity_provider" {
  value = google_iam_workload_identity_pool_provider.github.name
}

output "app_bucket" {
  value = google_storage_bucket.app.name
}
