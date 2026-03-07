# Restore domain mappings for custom domains
resource "google_cloud_run_domain_mapping" "frontend_domain" {
  count    = var.use_custom_domains ? 1 : 0
  location = var.region
  name     = var.frontend_domain

  metadata {
    namespace = var.project_id
  }

  spec {
    route_name = google_cloud_run_v2_service.cortex_frontend.name
  }

  depends_on = [google_cloud_run_v2_service.cortex_frontend]
}

resource "google_cloud_run_domain_mapping" "backend_domain" {
  count    = var.use_custom_domains ? 1 : 0
  location = var.region
  name     = var.backend_domain

  metadata {
    namespace = var.project_id
  }

  spec {
    route_name = google_cloud_run_v2_service.cortex_backend.name
  }

  depends_on = [google_cloud_run_v2_service.cortex_backend]
}
