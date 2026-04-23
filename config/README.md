# config/

Reference manifests for the ECK on AKS deployment. These mirror the resources
that Terraform deploys and are provided here for documentation and manual apply
reference only.

**Terraform is the source of truth.** Do not edit these files for routine
changes — modify the Terraform configuration instead. These are intended for
cases where you need to inspect or apply a resource manually outside Terraform
(e.g. during debugging or a fresh cluster bootstrap).

## Domain

`eck-on-aks.cascavel-security.net`

## Applying manually

```bash
kubectl apply -f config/<file>.yaml
```

Ensure the ECK operator and cert-manager are fully ready before applying
dependent resources.

## Resource reference

| File | Kind | API Group / CRD |
|------|------|-----------------|
| `cluster-issuer.yaml` | ClusterIssuer | `cert-manager.io/v1` |
| `elasticsearch.yaml` | Elasticsearch | `elasticsearch.k8s.elastic.co/v1` |
| `kibana.yaml` | Kibana | `kibana.k8s.elastic.co/v1` |
| `fleet-server.yaml` | Agent | `agent.k8s.elastic.co/v1alpha1` |
| `apm-server.yaml` | ApmServer | `apm.k8s.elastic.co/v1` |

All ECK resources are deployed into the `elastic-system` namespace.

## Dependencies

- `cluster-issuer.yaml` requires cert-manager to be installed and DNS to be
  delegated before Let's Encrypt certificates can issue.
- `elasticsearch.yaml` must be applied before Kibana, Fleet Server, or APM
  Server, as they all hold an `elasticsearchRef` pointing to it.
- `fleet-server.yaml` requires a `fleet-server` ServiceAccount with the
  appropriate RBAC bindings (managed by Terraform).
