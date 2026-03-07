
variable "project_id" {
  description = "The GCP project ID where resources will be created"
  type        = string
}

variable "region" {
  description = "The GCP region where resources will be created"
  type        = string
  default     = "us-central1"
}

variable "zone" {
  description = "The GCP zone where resources will be created"
  type        = string
  default     = "us-central1-a"
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "firestore_location_id" {
  description = "Firestore database location"
  type        = string
  default     = "nam5"
}

variable "deployer_member" {
  description = "IAM member allowed to act as SAs at deploy time"
  type        = string
  default     = "user:EMAIL@EXAMPLE.COM"
}

variable "frontend_tag" {
  description = "Docker image tag for the frontend service"
  type        = string
  default     = "latest"

  validation {
    condition     = length(var.frontend_tag) > 0
    error_message = "Frontend tag cannot be empty."
  }
}

variable "backend_tag" {
  description = "Docker image tag for the backend service"
  type        = string
  default     = "latest"

  validation {
    condition     = length(var.backend_tag) > 0
    error_message = "Backend tag cannot be empty."
  }
}

# Domain configuration variables
variable "frontend_domain" {
  description = "Custom domain for the frontend service"
  type        = string
  default     = "cortex.exmaplesite.com"
}

variable "backend_domain" {
  description = "Custom domain for the backend API service"
  type        = string
  default     = "cortex-api.examplesite.com"
}

variable "use_custom_domains" {
  description = "Whether to use custom domains or default Cloud Run URLs"
  type        = bool
  default     = true
}

variable "allowed_origins" {
  description = "List of allowed CORS origins for the backend API"
  type        = list(string)
  default = [
    "https://cortex.examplesite.com",
    "http://localhost:3000"
  ]
}

variable "allowed_hosts" {
  description = "List of allowed hosts for the backend API"
  type        = list(string)
  default = [
    "cortex-api.examplesite.com",
    "*.run.app"
  ]
}

variable "backend_ingress_mode" {
  description = "Ingress mode for backend Cloud Run service. Options: 'all' (public), 'internal' (private), 'internal-and-cloud-load-balancing' (private with LB/API Gateway access). For maximum security, use 'internal-and-cloud-load-balancing' with API Gateway."
  type        = string
  default     = "all" # Change to "internal-and-cloud-load-balancing" for private backend with API Gateway
  
  validation {
    condition     = contains(["all", "internal", "internal-and-cloud-load-balancing"], var.backend_ingress_mode)
    error_message = "backend_ingress_mode must be one of: 'all', 'internal', 'internal-and-cloud-load-balancing'"
  }
}

variable "enable_cloud_armor" {
  description = "Enable Cloud Armor security policy for backend API (recommended for production)"
  type        = bool
  default     = true
}
