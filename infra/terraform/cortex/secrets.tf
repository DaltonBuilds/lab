# Create Secret Manager secrets
resource "google_secret_manager_secret" "openai_api_key" {
  secret_id = "openai-api-key"

  replication {
    auto {}
  }

  depends_on = [google_project_service.required_apis]
}

resource "google_secret_manager_secret_iam_member" "openai_accessor_backend" {
  secret_id = google_secret_manager_secret.openai_api_key.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.backend_service.email}"
}

# Anthropic API Key Secret
resource "google_secret_manager_secret" "anthropic_api_key" {
  secret_id = "anthropic-api-key"

  replication {
    auto {}
  }

  depends_on = [google_project_service.required_apis]
}

resource "google_secret_manager_secret_iam_member" "anthropic_accessor_backend" {
  secret_id = google_secret_manager_secret.anthropic_api_key.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.backend_service.email}"
}

# Gemini API Key Secret
resource "google_secret_manager_secret" "gemini_api_key" {
  secret_id = "gemini-api-key"

  replication {
    auto {}
  }

  depends_on = [google_project_service.required_apis]
}

resource "google_secret_manager_secret_iam_member" "gemini_accessor_backend" {
  secret_id = google_secret_manager_secret.gemini_api_key.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.backend_service.email}"
}

# Groq API Key Secret
resource "google_secret_manager_secret" "groq_api_key" {
  secret_id = "groq-api-key"

  replication {
    auto {}
  }

  depends_on = [google_project_service.required_apis]
}

resource "google_secret_manager_secret_iam_member" "groq_accessor_backend" {
  secret_id = google_secret_manager_secret.groq_api_key.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.backend_service.email}"
}

# Store Firebase Admin credentials in Secret Manager (environment-specific)
resource "google_secret_manager_secret" "firebase_admin_credentials" {
  secret_id = "firebase-admin-credentials-${var.environment}"

  replication {
    auto {}
  }

  depends_on = [google_project_service.required_apis]
}

resource "google_secret_manager_secret_version" "firebase_admin_credentials" {
  secret      = google_secret_manager_secret.firebase_admin_credentials.id
  secret_data = base64decode(google_service_account_key.firebase_admin_key.private_key)
}

# Allow backend service to access Firebase Admin credentials
resource "google_secret_manager_secret_iam_member" "firebase_admin_accessor_backend" {
  secret_id = google_secret_manager_secret.firebase_admin_credentials.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.backend_service.email}"
}

# Firebase Client Configuration Secrets (for frontend build)
# These are public client-side config values, but stored in Secrets Manager for consistency
resource "google_secret_manager_secret" "firebase_api_key" {
  secret_id = "firebase-api-key-${var.environment}"

  replication {
    auto {}
  }

  depends_on = [google_project_service.required_apis]
}

resource "google_secret_manager_secret" "firebase_auth_domain" {
  secret_id = "firebase-auth-domain-${var.environment}"

  replication {
    auto {}
  }

  depends_on = [google_project_service.required_apis]
}

resource "google_secret_manager_secret" "firebase_project_id" {
  secret_id = "firebase-project-id-${var.environment}"

  replication {
    auto {}
  }

  depends_on = [google_project_service.required_apis]
}

resource "google_secret_manager_secret" "firebase_storage_bucket" {
  secret_id = "firebase-storage-bucket-${var.environment}"

  replication {
    auto {}
  }

  depends_on = [google_project_service.required_apis]
}

resource "google_secret_manager_secret" "firebase_messaging_sender_id" {
  secret_id = "firebase-messaging-sender-id-${var.environment}"

  replication {
    auto {}
  }

  depends_on = [google_project_service.required_apis]
}

resource "google_secret_manager_secret" "firebase_app_id" {
  secret_id = "firebase-app-id-${var.environment}"

  replication {
    auto {}
  }

  depends_on = [google_project_service.required_apis]
}

# Grant deployer access to Firebase client config secrets (for build-time access)
resource "google_secret_manager_secret_iam_member" "firebase_api_key_accessor_deployer" {
  secret_id = google_secret_manager_secret.firebase_api_key.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = var.deployer_member
}

resource "google_secret_manager_secret_iam_member" "firebase_auth_domain_accessor_deployer" {
  secret_id = google_secret_manager_secret.firebase_auth_domain.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = var.deployer_member
}

resource "google_secret_manager_secret_iam_member" "firebase_project_id_accessor_deployer" {
  secret_id = google_secret_manager_secret.firebase_project_id.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = var.deployer_member
}

resource "google_secret_manager_secret_iam_member" "firebase_storage_bucket_accessor_deployer" {
  secret_id = google_secret_manager_secret.firebase_storage_bucket.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = var.deployer_member
}

resource "google_secret_manager_secret_iam_member" "firebase_messaging_sender_id_accessor_deployer" {
  secret_id = google_secret_manager_secret.firebase_messaging_sender_id.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = var.deployer_member
}

resource "google_secret_manager_secret_iam_member" "firebase_app_id_accessor_deployer" {
  secret_id = google_secret_manager_secret.firebase_app_id.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = var.deployer_member
}

# Grant Cloud Build service account access to Firebase client config secrets (for CI/CD builds)
resource "google_secret_manager_secret_iam_member" "firebase_api_key_accessor_cloud_build" {
  secret_id = google_secret_manager_secret.firebase_api_key.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.cloud_build.email}"
}

resource "google_secret_manager_secret_iam_member" "firebase_auth_domain_accessor_cloud_build" {
  secret_id = google_secret_manager_secret.firebase_auth_domain.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.cloud_build.email}"
}

resource "google_secret_manager_secret_iam_member" "firebase_project_id_accessor_cloud_build" {
  secret_id = google_secret_manager_secret.firebase_project_id.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.cloud_build.email}"
}

resource "google_secret_manager_secret_iam_member" "firebase_storage_bucket_accessor_cloud_build" {
  secret_id = google_secret_manager_secret.firebase_storage_bucket.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.cloud_build.email}"
}

resource "google_secret_manager_secret_iam_member" "firebase_messaging_sender_id_accessor_cloud_build" {
  secret_id = google_secret_manager_secret.firebase_messaging_sender_id.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.cloud_build.email}"
}

resource "google_secret_manager_secret_iam_member" "firebase_app_id_accessor_cloud_build" {
  secret_id = google_secret_manager_secret.firebase_app_id.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.cloud_build.email}"
}
