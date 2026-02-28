# Create a service account for the backend service
resource "google_service_account" "backend_service" {
  account_id   = "cortex-backend"
  display_name = "Cortex Backend Service Account"
  description  = "Service account for Cortex backend API service"

  depends_on = [google_project_service.required_apis]
}

# Grant necessary permissions to the service account
resource "google_project_iam_member" "backend_permissions" {
  for_each = toset([
    "roles/datastore.user",               # Firestore access
    "roles/secretmanager.secretAccessor", # Secret Manager access
    "roles/artifactregistry.reader",      # Artifact Registry access
  ])

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.backend_service.email}"
}

# Create Firestore database
resource "google_firestore_database" "cortex_db" {
  project     = var.project_id
  name        = "(default)"
  location_id = "nam5"
  type        = "FIRESTORE_NATIVE"

  depends_on = [google_project_service.required_apis]
}

# Create Artifact Registry repository for Docker images
resource "google_artifact_registry_repository" "cortex_repo" {
  location      = var.region
  repository_id = "cortex"
  description   = "Docker repository for Cortex services (backend and frontend)"
  format        = "DOCKER"

  depends_on = [google_project_service.required_apis]
}

# Firebase Admin Service Account for token validation
resource "google_service_account" "firebase_admin" {
  account_id   = "firebase-admin-${var.environment}"
  display_name = "Firebase Admin Service Account for ${var.environment}"
  description  = "Service account for Firebase Admin SDK token validation"

  depends_on = [google_project_service.required_apis]
}

# Generate service account key for Firebase Admin SDK
resource "google_service_account_key" "firebase_admin_key" {
  service_account_id = google_service_account.firebase_admin.name
  public_key_type    = "TYPE_X509_PEM_FILE"
}

# Grant Firebase Admin permissions with least privilege principle
# Using Firebase Auth specific roles instead of broader Firebase roles for security
resource "google_project_iam_member" "firebase_admin_auth" {
  project = var.project_id
  role    = "roles/firebaseauth.admin"
  member  = "serviceAccount:${google_service_account.firebase_admin.email}"
}

# IAM configuration for Cloud Run services
# 
# SECURITY NOTE: The backend access configuration depends on ingress mode:
# - If ingress = "all": Requires allUsers or allAuthenticatedUsers (for public access)
# - If ingress = "internal": No IAM needed (VPC-only access)
# - If ingress = "internal-and-cloud-load-balancing": Only Load Balancer/API Gateway needs invoker role
#
# For maximum security with Firebase Auth:
# 1. Set backend_ingress_mode = "internal-and-cloud-load-balancing"
# 2. Deploy API Gateway (see api_gateway.tf) as public entry point
# 3. Grant API Gateway service account invoker role (not allUsers)
# 4. Application-level Firebase Auth handles user authentication

# Backend access - conditional based on ingress mode
resource "google_cloud_run_v2_service_iam_member" "backend_public_access" {
  count = var.backend_ingress_mode == "all" ? 1 : 0
  
  location = google_cloud_run_v2_service.cortex_backend.location
  name     = google_cloud_run_v2_service.cortex_backend.name
  role     = "roles/run.invoker"
  member   = "allUsers" # Required for public access with Firebase Auth from browsers

  depends_on = [google_cloud_run_v2_service.cortex_backend]
}

# For private backend with API Gateway, grant invoker to API Gateway service account
# This is configured in api_gateway.tf when using private ingress mode

resource "google_cloud_run_v2_service_iam_member" "frontend_public_access" {
  location = google_cloud_run_v2_service.cortex_frontend.location
  name     = google_cloud_run_v2_service.cortex_frontend.name
  role     = "roles/run.invoker"
  member   = "allUsers"

  depends_on = [google_cloud_run_v2_service.cortex_frontend]
}

# Cloud Build service account for CI/CD
resource "google_service_account" "cloud_build" {
  account_id   = "cortex-cloud-build"
  display_name = "Cortex Cloud Build Service Account"
  description  = "Service account for Cloud Build CI/CD pipeline"

  depends_on = [google_project_service.required_apis]
}

# Cloud Build permissions
resource "google_project_iam_member" "cloud_build_permissions" {
  for_each = toset([
    "roles/run.admin",                    # Deploy to Cloud Run
    "roles/artifactregistry.writer",      # Push images to Artifact Registry
    "roles/iam.serviceAccountUser",       # Use service accounts
    "roles/secretmanager.secretAccessor", # Access secrets
  ])

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.cloud_build.email}"
}

# Frontend runtime service account
resource "google_service_account" "frontend_service" {
  account_id   = "cortex-frontend"
  display_name = "Cortex Frontend Service Account"
  description  = "Runtime identity for Cortex frontend Cloud Run service"

  depends_on = [google_project_service.required_apis]
}

# Allow the deployer to act as the frontend service account
resource "google_service_account_iam_member" "frontend_actas_for_deployer" {
  service_account_id = google_service_account.frontend_service.name
  role               = "roles/iam.serviceAccountUser"
  member             = var.deployer_member
}

# Frontend permissions
resource "google_project_iam_member" "frontend_permissions" {
  for_each = toset([
    "roles/artifactregistry.reader",
  ])
  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.frontend_service.email}"
}

