# Cloud Run service for backend API
resource "google_cloud_run_v2_service" "cortex_backend" {
  provider = google-beta
  name     = "cortex-backend"
  location = var.region

  # Ingress configuration for security
  # Options:
  # - "all": Public access (current default, requires allUsers invoker)
  # - "internal": Only accessible from same project (VPC, other Cloud Run services)
  # - "internal-and-cloud-load-balancing": Private but accessible via Load Balancer/API Gateway
  ingress = var.backend_ingress_mode

  template {
    service_account = google_service_account.backend_service.email
    timeout         = "900s" # 15 minutes for long-running AI requests

    # Resource limits for cost optimization
    scaling {
      min_instance_count = 0
      max_instance_count = 10
    }

    containers {
      # Backend
      image = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.cortex_repo.repository_id}/backend:${var.backend_tag}"

      ports {
        container_port = 8080
      }

      # Resource limits
      resources {
        limits = {
          cpu    = "1"
          memory = "1Gi"
        }
      }

      # Environment variables
      env {
        name  = "PROJECT_ID"
        value = var.project_id
      }

      env {
        name  = "REGION"
        value = var.region
      }

      env {
        name  = "ENVIRONMENT"
        value = var.environment
      }

      env {
        name  = "LOG_LEVEL"
        value = "INFO"
      }

      env {
        name  = "LOG_FORMAT"
        value = "json"
      }

      env {
        name  = "FIRESTORE_DATABASE_ID"
        value = "(default)"
      }

      # CORS configuration - includes custom domains and fallback URLs
      env {
        name  = "ALLOWED_ORIGINS"
        value = jsonencode(var.allowed_origins)
      }

      env {
        name  = "ALLOWED_HOSTS"
        value = jsonencode(var.allowed_hosts)
      }

      # Custom domain configuration
      env {
        name  = "CUSTOM_DOMAIN"
        value = var.backend_domain
      }

      env {
        name  = "USE_CUSTOM_DOMAINS"
        value = tostring(var.use_custom_domains)
      }

      # Secret environment variables
      env {
        name = "OPENAI_API_KEY"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.openai_api_key.secret_id
            version = "latest"
          }
        }
      }

      env {
        name = "ANTHROPIC_API_KEY"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.anthropic_api_key.secret_id
            version = "latest"
          }
        }
      }

      env {
        name = "GEMINI_API_KEY"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.gemini_api_key.secret_id
            version = "latest"
          }
        }
      }

      env {
        name = "GROQ_API_KEY"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.groq_api_key.secret_id
            version = "latest"
          }
        }
      }
    }
  }

  depends_on = [
    google_project_service.required_apis,
    google_artifact_registry_repository.cortex_repo,
    google_secret_manager_secret.openai_api_key,
    google_secret_manager_secret_iam_member.openai_accessor_backend,
    google_secret_manager_secret.anthropic_api_key,
    google_secret_manager_secret_iam_member.anthropic_accessor_backend,
    google_secret_manager_secret.gemini_api_key,
    google_secret_manager_secret_iam_member.gemini_accessor_backend,
    google_secret_manager_secret.groq_api_key,
    google_secret_manager_secret_iam_member.groq_accessor_backend,
    google_project_iam_member.backend_permissions
  ]
}

# Cloud Run service for frontend
resource "google_cloud_run_v2_service" "cortex_frontend" {
  provider = google-beta
  name     = "cortex-frontend"
  location = var.region

  template {
    # Resource limits for cost optimization
    service_account = google_service_account.frontend_service.email

    scaling {
      min_instance_count = 0
      max_instance_count = 5
    }

    containers {
      # Frontend
      image = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.cortex_repo.repository_id}/frontend:${var.frontend_tag}"

      ports {
        container_port = 3000
      }

      # Resource limits (frontend needs less resources)
      resources {
        limits = {
          cpu    = "1"
          memory = "512Mi"
        }
      }

      # Environment variables for frontend
      env {
        name  = "NODE_ENV"
        value = "production"
      }

      # Backend API URL - use custom domain if enabled, otherwise Cloud Run URL
      env {
        name  = "NEXT_PUBLIC_API_URL"
        value = var.use_custom_domains ? "https://${var.backend_domain}/api/v1" : "${google_cloud_run_v2_service.cortex_backend.uri}/api/v1"
      }

      # Custom domain configuration for frontend
      env {
        name  = "CUSTOM_DOMAIN"
        value = var.frontend_domain
      }

      env {
        name  = "USE_CUSTOM_DOMAINS"
        value = tostring(var.use_custom_domains)
      }
    }
  }

  depends_on = [
    google_project_service.required_apis,
    google_service_account.frontend_service,
    google_service_account_iam_member.frontend_actas_for_deployer,
    google_project_iam_member.frontend_permissions,
    google_cloud_run_v2_service.cortex_backend,
  ]
}

