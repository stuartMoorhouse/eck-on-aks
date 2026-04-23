data "kubernetes_service" "app_routing_ingress" {
  metadata {
    name      = "nginx"
    namespace = "app-routing-system"
  }

  depends_on = [null_resource.aks_credentials]
}

locals {
  ingress_ip = data.kubernetes_service.app_routing_ingress.status[0].load_balancer[0].ingress[0].ip

  ingress_annotations = {
    "cert-manager.io/cluster-issuer" = "letsencrypt-prod"
  }
  ingress_class = "webapprouting.kubernetes.azure.com"
  ingress_deps = [
    null_resource.cluster_issuer,
  ]
}

resource "azurerm_dns_a_record" "kibana" {
  name                = "kibana"
  zone_name           = azurerm_dns_zone.main.name
  resource_group_name = azurerm_resource_group.main.name
  ttl                 = 300
  records             = [local.ingress_ip]
  tags                = var.tags
}


resource "kubernetes_manifest" "ingress_kibana" {
  manifest = {
    apiVersion = "networking.k8s.io/v1"
    kind       = "Ingress"
    metadata = {
      name        = "kibana"
      namespace   = "elastic-system"
      annotations = local.ingress_annotations
    }
    spec = {
      ingressClassName = local.ingress_class
      tls = [
        {
          hosts      = ["kibana.${var.dns_zone_name}"]
          secretName = "kibana-tls"
        }
      ]
      rules = [
        {
          host = "kibana.${var.dns_zone_name}"
          http = {
            paths = [
              {
                path     = "/"
                pathType = "Prefix"
                backend = {
                  service = {
                    name = "kibana-kb-http"
                    port = { number = 5601 }
                  }
                }
              }
            ]
          }
        }
      ]
    }
  }

  depends_on = [
    null_resource.kibana,
    null_resource.cluster_issuer,
  ]
}

