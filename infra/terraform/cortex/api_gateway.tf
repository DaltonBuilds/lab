# API Gateway configuration for private backend access
# This file implements Option 1: API Gateway + Private Cloud Run
# 
# ARCHITECTURE:
# Browser → API Gateway (public) → Private Cloud Run Backend (internal-only)
#
# BENEFITS:
# - Backend is not publicly accessible (defense in depth)
# - API Gateway provides WAF, rate limiting, and monitoring
# - Single public entry point with centralized security
# - Application-level Firebase Auth still enforced
#
# USAGE:
# 1. Set backend_ingress_mode = "internal-and-cloud-load-balancing" in variables
# 2. Uncomment resources below
# 3. Update frontend API URL to use API Gateway endpoint
# 4. Run terraform apply

# Enable API Gateway API
# resource "google_project_service" "api_gateway_api" {
#   service = "apigateway.googleapis.com"
#   project = var.project_id
#
#   disable_on_destroy = false
#
#   depends_on = [google_project_service.required_apis]
# }
#
# # API Gateway API configuration
# resource "google_api_gateway_api" "cortex_backend_api" {
#   provider     = google-beta
#   api_id       = "cortex-backend-api-${var.environment}"
#   project      = var.project_id
#   display_name = "Cortex Backend API Gateway"
# }
#
# # API Gateway API config (OpenAPI spec)
# resource "google_api_gateway_api_config" "cortex_backend_config" {
#   provider      = google-beta
#   api           = google_api_gateway_api.cortex_backend_api.api_id
#   api_config_id = "cortex-backend-config-${var.environment}"
#   project       = var.project_id
#   display_name  = "Cortex Backend API Config"
#
#   openapi_documents {
#     document {
#       path     = "openapi.yaml"
#       contents = base64encode(templatefile("${path.module}/openapi.yaml", {
#         backend_url = google_cloud_run_v2_service.cortex_backend.uri
#       }))
#     }
#   }
#
#   gateway_config {
#     backend_config {
#       google_service_account = google_service_account.backend_service.email
#     }
#   }
#
#   depends_on = [
#     google_api_gateway_api.cortex_backend_api,
#     google_cloud_run_v2_service.cortex_backend,
#   ]
# }
#
# # API Gateway Gateway
# resource "google_api_gateway_gateway" "cortex_backend_gateway" {
#   provider   = google-beta
#   api_config = google_api_gateway_api_config.cortex_backend_config.id
#   gateway_id = "cortex-backend-gateway-${var.environment}"
#   project    = var.project_id
#   region     = var.region
#
#   depends_on = [google_api_gateway_api_config.cortex_backend_config]
# }
#
# # Grant API Gateway service account permission to invoke backend
# resource "google_cloud_run_v2_service_iam_member" "backend_api_gateway_invoker" {
#   location = google_cloud_run_v2_service.cortex_backend.location
#   name     = google_cloud_run_v2_service.cortex_backend.name
#   role     = "roles/run.invoker"
#   member   = "serviceAccount:${google_api_gateway_api.cortex_backend_api.managed_service}"
#
#   depends_on = [
#     google_cloud_run_v2_service.cortex_backend,
#     google_api_gateway_api.cortex_backend_api,
#   ]
# }
#
# # Output API Gateway URL
# output "api_gateway_url" {
#   description = "API Gateway endpoint URL for backend API"
#   value       = google_api_gateway_gateway.cortex_backend_gateway.default_hostname
# }

