provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}

# Configure the Google Cloud Beta Provider
provider "google-beta" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}
