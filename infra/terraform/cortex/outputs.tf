# Cloud-Native Second Brain - Terraform Outputs
# Owner: YOUR NAME 
# Project: Cloud-Native Second Brain
# Date: 2025-01-27

output "project_id" {
  description = "The GCP project ID"
  value       = var.project_id
}

output "region" {
  description = "The GCP region"
  value       = var.region
}

output "firestore_database_id" {
  description = "The Firestore database ID"
  value       = google_firestore_database.cortex_db.name
}

output "artifact_registry_repository" {
  description = "The Artifact Registry repository URL (repo root)"
  value       = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.cortex_repo.repository_id}"
}

# Helpful repo paths for CI to push to:
output "backend_image_repo" {
  description = "Container repo path for backend images (append :TAG)"
  value       = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.cortex_repo.repository_id}/backend"
}

output "frontend_image_repo" {
  description = "Container repo path for frontend images (append :TAG)"
  value       = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.cortex_repo.repository_id}/frontend"
}

output "backend_service_url" {
  description = "The backend Cloud Run service URL"
  value       = google_cloud_run_v2_service.cortex_backend.uri
}

output "frontend_service_url" {
  description = "The frontend Cloud Run service URL"
  value       = google_cloud_run_v2_service.cortex_frontend.uri
}

output "backend_service_account_email" {
  description = "The backend service account email"
  value       = google_service_account.backend_service.email
}

output "cloud_build_service_account_email" {
  description = "The Cloud Build service account email"
  value       = google_service_account.cloud_build.email
}

output "firebase_admin_service_account_email" {
  description = "The Firebase Admin service account email"
  value       = google_service_account.firebase_admin.email
}

output "secret_names" {
  description = "Names of created secrets in Secret Manager"
  value = {
    openai_api_key             = google_secret_manager_secret.openai_api_key.secret_id
    firebase_admin_credentials = google_secret_manager_secret.firebase_admin_credentials.secret_id
  }
}

output "firestore_location_id" {
  description = "The location ID of the Firestore database"
  value       = var.firestore_location_id
}

# Custom domain outputs
output "frontend_domain" {
  description = "The custom domain for the frontend service"
  value       = var.frontend_domain
}

output "backend_domain" {
  description = "The custom domain for the backend API service"
  value       = var.backend_domain
}

output "frontend_url" {
  description = "The frontend URL (custom domain if enabled, otherwise Cloud Run URL)"
  value       = var.use_custom_domains ? "https://${var.frontend_domain}" : google_cloud_run_v2_service.cortex_frontend.uri
}

output "backend_url" {
  description = "The backend API URL (custom domain if enabled, otherwise Cloud Run URL)"
  value       = var.use_custom_domains ? "https://${var.backend_domain}" : google_cloud_run_v2_service.cortex_backend.uri
}

output "api_base_url" {
  description = "The complete API base URL for frontend configuration"
  value       = var.use_custom_domains ? "https://${var.backend_domain}/api/v1" : "${google_cloud_run_v2_service.cortex_backend.uri}/api/v1"
}

output "domain_configuration" {
  description = "Domain configuration summary"
  value = {
    use_custom_domains = var.use_custom_domains
    frontend_domain    = var.frontend_domain
    backend_domain     = var.backend_domain
    allowed_origins    = var.allowed_origins
    allowed_hosts      = var.allowed_hosts
  }
}

# DNS configuration outputs
output "dns_records_required" {
  description = "DNS records that need to be configured for custom domains"
  value = var.use_custom_domains ? {
    frontend = {
      name   = split(".", var.frontend_domain)[0]
      type   = "CNAME"
      value  = "ghs.googlehosted.com."
      domain = var.frontend_domain
    }
    backend = {
      name   = split(".", var.backend_domain)[0]
      type   = "CNAME"
      value  = "ghs.googlehosted.com."
      domain = var.backend_domain
    }
  } : null
}

output "domain_mapping_status" {
  description = "Status of domain mappings (when using custom domains)"
  value = var.use_custom_domains ? {
    frontend_mapping = length(google_cloud_run_domain_mapping.frontend_domain) > 0 ? google_cloud_run_domain_mapping.frontend_domain[0].status : null
    backend_mapping  = length(google_cloud_run_domain_mapping.backend_domain) > 0 ? google_cloud_run_domain_mapping.backend_domain[0].status : null
  } : null
}

# Authentication configuration
output "authentication_status" {
  description = "Authentication configuration for Cloud Run services"
  value = {
    backend_authorized_users  = ["email@example.com]
    frontend_authorized_users = ["email@example.com"]
    public_access_removed     = true
    authentication_required   = true
  }
}
