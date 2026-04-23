resource "helm_release" "cert_manager" {
  name             = "cert-manager"
  repository       = "https://charts.jetstack.io"
  chart            = "cert-manager"
  version          = var.cert_manager_version
  namespace        = "cert-manager"
  create_namespace = true

  set {
    name  = "installCRDs"
    value = "true"
  }

  depends_on = [azurerm_kubernetes_cluster.main, null_resource.aks_credentials]
}

resource "helm_release" "eck_operator" {
  name             = "eck-operator"
  repository       = "https://helm.elastic.co"
  chart            = "eck-operator"
  version          = var.eck_operator_version
  namespace        = "elastic-system"
  create_namespace = true

  depends_on = [azurerm_kubernetes_cluster.main, null_resource.aks_credentials]
}

resource "null_resource" "wait_for_cert_manager" {
  provisioner "local-exec" {
    command = "kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=cert-manager -n cert-manager --timeout=180s"
  }

  depends_on = [helm_release.cert_manager]
}

resource "null_resource" "wait_for_eck_operator" {
  provisioner "local-exec" {
    command = "kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=elastic-operator -n elastic-system --timeout=300s"
  }

  depends_on = [helm_release.eck_operator]
}

resource "null_resource" "cluster_issuer" {
  triggers = {
    acme_email = var.acme_contact_email
  }

  provisioner "local-exec" {
    environment = {
      MANIFEST = <<-YAML
        apiVersion: cert-manager.io/v1
        kind: ClusterIssuer
        metadata:
          name: letsencrypt-prod
        spec:
          acme:
            server: https://acme-v02.api.letsencrypt.org/directory
            email: ${var.acme_contact_email}
            privateKeySecretRef:
              name: letsencrypt-prod-account-key
            solvers:
            - http01:
                ingress:
                  ingressClassName: webapprouting.kubernetes.azure.com
        YAML
    }
    command = "echo \"$MANIFEST\" | kubectl apply -f -"
  }

  depends_on = [null_resource.wait_for_cert_manager]
}
