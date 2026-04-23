# Delegate the Azure-managed subdomain in Cloudflare. Azure assigns nameservers
# after zone creation; trimsuffix strips the trailing dot that Azure appends.
resource "cloudflare_record" "eck_ns" {
  for_each = toset(azurerm_dns_zone.main.name_servers)

  zone_id = var.cloudflare_zone_id
  name    = "eck-on-aks"
  type    = "NS"
  content = trimsuffix(each.value, ".")
  ttl     = 300
}
