data "google_project" "project" {
  project_id = var.project_id
}

# Enable required APIs
resource "google_project_service" "required_apis" {
  for_each = toset([
    "run.googleapis.com",              # Cloud Run
    "firestore.googleapis.com",        # Firestore
    "artifactregistry.googleapis.com", # Artifact Registry
    "secretmanager.googleapis.com",    # Secret Manager
    "iam.googleapis.com",              # IAM (for service accounts)
    "cloudbuild.googleapis.com",       # Cloud Build (for CI/CD)
    "firebase.googleapis.com",         # Firebase (for Firebase Admin SDK)
  ])

  service = each.value
  project = var.project_id

  disable_on_destroy = false
}
