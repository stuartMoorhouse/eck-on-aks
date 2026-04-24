variable "subscription_id" {
  description = "Azure subscription ID — set via TF_VAR_subscription_id or terraform.tfvars"
  type        = string
}

variable "tenant_id" {
  description = "Azure tenant ID — set via TF_VAR_tenant_id or terraform.tfvars"
  type        = string
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
  description = "Azure DNS zone to create (subdomain of your Cloudflare-managed domain, e.g. eck.example.com)"
  type        = string
}

variable "cloudflare_zone_id" {
  description = "Cloudflare zone ID for the parent domain (set via TF_VAR_cloudflare_zone_id)"
  type        = string
  sensitive   = true
}

variable "aks_node_count" {
  description = "Maximum number of AKS nodes (min is always 1)"
  type        = number
  default     = 6
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
}

variable "tags" {
  description = "Tags applied to all Azure resources. Set values in tags.auto.tfvars (gitignored)."
  type        = map(string)
  default     = {}
}
