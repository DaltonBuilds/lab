# Security configuration for defense in depth
# This file implements best practices for securing Cloud Run services

# ============================================================================
# OPTION 1: Cloud Armor Security Policy (Recommended for immediate implementation)
# ============================================================================
# Provides DDoS protection and rate limiting for public-facing services
# This is the simplest enhancement to your current setup

# Enable Cloud Armor API
resource "google_project_service" "cloud_armor_api" {
  service = "compute.googleapis.com" # Cloud Armor is part of Compute Engine
  project = var.project_id

  disable_on_destroy = false

  depends_on = [google_project_service.required_apis]
}

# Cloud Armor security policy for backend API
# 
# ⚠️ COST WARNING: Cloud Armor requires a Load Balancer ($18/month) or API Gateway ($3 per million requests after free tier)
# This adds significant cost. For low-traffic apps, consider application-level rate limiting instead.
#
# For direct Cloud Run access without additional infrastructure, application-level rate limiting is recommended.
# See: https://fastapi.tiangolo.com/advanced/middleware/#rate-limiting
resource "google_compute_security_policy" "backend_security_policy" {
  count = var.enable_cloud_armor ? 1 : 0
  
  name        = "cortex-backend-security-${var.environment}"
  description = "Security policy for Cortex backend API with rate limiting and DDoS protection"

  # Default rule: Allow all traffic (application-level auth handles authorization)
  rule {
    action   = "allow"
    priority = "2147483647" # Lowest priority (default rule)
    description = "Default allow rule - application-level auth enforces access control"
    
    match {
      versioned_expr = "SRC_IPS_V1"
      config {
        src_ip_ranges = ["*"]
      }
    }
  }

  # Rate limiting rule: Prevent abuse
  rule {
    action   = "rate_based_ban"
    priority = "1000"
    description = "Rate limit: 100 requests per minute per IP, ban for 5 minutes if exceeded"
    
    rate_limit_options {
      conform_action = "allow"
      exceed_action  = "deny(429)"
      enforce_on_key = "IP"
      
      rate_limit_threshold {
        count        = 100
        interval_sec = 60
      }
      
      ban_duration_sec = 300 # 5 minutes
    }
    
    match {
      versioned_expr = "SRC_IPS_V1"
      config {
        src_ip_ranges = ["*"]
      }
    }
  }

  # Block known bad IPs (example - customize as needed)
  # rule {
  #   action   = "deny(403)"
  #   priority = "100"
  #   description = "Block known malicious IPs"
  #   
  #   match {
  #     versioned_expr = "SRC_IPS_V1"
  #     config {
  #       src_ip_ranges = ["1.2.3.4/32"] # Add your blocked IPs here
  #     }
  #   }
  # }

  depends_on = [google_project_service.cloud_armor_api]
}

# ============================================================================
# OPTION 2: Private Cloud Run with Internal Ingress (Most Secure)
# ============================================================================
# Uncomment this section to make the backend private and accessible only via:
# - API Gateway (recommended)
# - Cloud Load Balancer
# - Other Cloud Run services in the same project
#
# NOTE: This requires additional infrastructure (API Gateway or Load Balancer)
# to route public traffic to the private backend. See api_gateway.tf for implementation.


# ============================================================================
# Security Best Practices Documentation
# ============================================================================
# 
# DEFENSE IN DEPTH LAYERS (from outer to inner):
#
# 1. NETWORK LAYER (Cloud Armor / Load Balancer)
#    - DDoS protection
#    - Rate limiting
#    - IP filtering
#    - WAF rules
#
# 2. INGRESS LAYER (Cloud Run Ingress Settings)
#    - Private endpoints (internal-only access)
#    - IAM-based invoker permissions
#
# 3. APPLICATION LAYER (Your FastAPI Backend)
#    - Firebase Auth token validation
#    - CORS restrictions
#    - Request validation
#
# 4. DATA LAYER (Firestore / Secrets)
#    - Service account permissions (least privilege)
#    - Secret Manager access controls
#
# RECOMMENDED PRODUCTION SETUP:
# - Cloud Armor security policy (this file)
# - Private Cloud Run backend (ingress: internal-and-cloud-load-balancing)
# - API Gateway or Load Balancer as public entry point
# - Application-level Firebase Auth (already implemented)
# - Service account with least privilege (already implemented)

