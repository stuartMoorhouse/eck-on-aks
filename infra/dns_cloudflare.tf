# Delegate the Azure-managed subdomain in Cloudflare. Azure assigns nameservers
# after zone creation; trimsuffix strips the trailing dot that Azure appends.
resource "cloudflare_record" "eck_ns" {
  count = 4

  zone_id = var.cloudflare_zone_id
  name    = "eck-on-aks"
  type    = "NS"
  content = trimsuffix(tolist(azurerm_dns_zone.main.name_servers)[count.index], ".")
  ttl     = 300
}
