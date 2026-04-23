variable "subscription_id" {
  description = "Azure subscription ID"
  type        = string
  default     = "YOUR_SUBSCRIPTION_ID"
}

variable "tenant_id" {
  description = "Azure tenant ID (Elastic: YOUR_TENANT_ID)"
  type        = string
  default     = "YOUR_TENANT_ID"
}

variable "location" {
  description = "Azure region for all resources"
  type        = string
  default     = "West Europe"
}

variable "prefix" {
  description = "Resource name prefix"
  type        = string
  default     = "eck-on-aks"
}

variable "dns_zone_name" {
  description = "Azure DNS zone to create (subdomain of your Cloudflare-managed domain)"
  type        = string
  default     = "eck-on-aks.cascavel-security.net"
}

variable "cloudflare_zone_id" {
  description = "Cloudflare zone ID for the parent domain (set via TF_VAR_cloudflare_zone_id)"
  type        = string
  sensitive   = true
}

variable "aks_node_count" {
  description = "Number of AKS nodes"
  type        = number
  default     = 3
}

variable "aks_node_sku" {
  description = "AKS node VM size"
  type        = string
  default     = "Standard_D4s_v3"
}

variable "elastic_version" {
  description = "Elastic Stack version to deploy via ECK"
  type        = string
  default     = "9.3.0"
}

variable "eck_operator_version" {
  description = "ECK operator Helm chart version (must support elastic_version)"
  type        = string
  default     = "3.3.1"
}

variable "cert_manager_version" {
  description = "cert-manager Helm chart version"
  type        = string
  default     = "v1.14.4"
}

variable "acme_contact_email" {
  description = "Email address for Let's Encrypt ACME account notifications"
  type        = string
  default     = "stuart.moorhouse@elastic.co"
}

variable "tags" {
  description = "Tags applied to all Azure resources. Set values in tags.auto.tfvars (gitignored)."
  type        = map(string)
  default     = {}
}
