# ECK on AKS

Elastic Cloud on Kubernetes (ECK) deployed on Azure Kubernetes Service (AKS),
managed with Terraform.

## Architecture

- **AKS cluster**: 3 nodes (`Standard_D4s_v3`, 4 vCPU / 16 GB), multi-zone
- **ECK operator**: v3.3.1, manages Elasticsearch and Kibana
- **Elasticsearch**: 3-node cluster, all nodes master-eligible + data (combined roles per Elastic docs best practice for clusters of this size)
- **DNS**: Azure DNS zone delegated from Cloudflare; subdomain set via `dns_zone_name` variable
- **TLS**: Let's Encrypt via cert-manager + Azure App Routing ingress
- **Snapshots**: Azure Blob Storage, daily SLM policy

## Prerequisites

- Azure CLI (`az login`), `kubectl`, `terraform`, `helm`
- Cloudflare account with a domain you control
- The following environment variables set before running `scripts/deploy.sh`:

```bash
export TF_VAR_subscription_id=<azure-subscription-id>
export TF_VAR_tenant_id=<azure-tenant-id>
export TF_VAR_dns_zone_name=<subdomain-to-create, e.g. eck.example.com>
export TF_VAR_acme_contact_email=<your-email>
export CLOUDFLARE_API_TOKEN=<cloudflare-api-token>
export TF_VAR_cloudflare_zone_id=<cloudflare-zone-id-for-your-root-domain>
```

## Deploy

```bash
# Verify Azure subscription
scripts/get-secrets.sh

# Full deploy
scripts/deploy.sh

# Post-deploy: wait for health + print creds
scripts/configure.sh

# Configure snapshot repository + SLM policy
scripts/setup-snapshots.sh
```

## Access

| Service | URL                                        |
|---------|--------------------------------------------|
| Kibana  | `https://kibana.<dns_zone_name>`           |

`<dns_zone_name>` is the value of the `dns_zone_name` Terraform variable (e.g. `eck.example.com`).

## DNS and Traffic Path

**DNS resolution** for `kibana.<dns_zone_name>`:

1. The registrar delegates `<your-root-domain>` to Cloudflare nameservers.
2. Cloudflare holds NS records delegating `<dns_zone_name>` to Azure DNS (Terraform creates this delegation automatically).
3. Azure DNS holds the A record: `kibana → <load-balancer-ip>` (assigned by Azure on deploy).

Cloudflare is not in the traffic path — it only redirects DNS lookups to Azure DNS. Once the browser resolves the IP, all traffic goes directly to Azure.

**Traffic path** once the IP is resolved:

```
Browser (HTTPS)
    → Azure Public IP (<load-balancer-ip>)
    → Azure Load Balancer (MC_* resource group, port 443)
    → AKS node (nginx ingress pod in app-routing-system namespace)
    → Kibana Service (ClusterIP, port 5601)
    → Kibana pod
```

TLS is terminated at the nginx ingress using a Let's Encrypt certificate managed by cert-manager.

## Day-2 Operations

### Upgrading Elasticsearch version

Change `elastic_version` in `variables.tf` (or pass `-var`), then re-apply. ECK performs a
rolling upgrade automatically, respecting the `changeBudget` in the spec. Constraints:

- You can only upgrade one major version at a time.
- ECK operator 3.3.1 supports Elastic Stack 8.x and 9.x. If upgrading the operator itself,
  update `eck_operator_version` in `variables.tf` first, apply, then update `elastic_version`.
- Monitor progress: `kubectl get elasticsearch -n elastic-system -w`

### Checking cluster health

```bash
# Elasticsearch health
kubectl get elasticsearch -n elastic-system

# Pod status
kubectl get pods -n elastic-system

# Elastic user password
kubectl get secret elasticsearch-es-elastic-user -n elastic-system \
  -o jsonpath='{.data.elastic}' | base64 -d

# Tail operator logs
kubectl logs -n elastic-system statefulset/elastic-operator -f
```

### Checking snapshot status

```bash
# After running scripts/setup-snapshots.sh, verify the repository
KIBANA_URL=$(cd infra && terraform output -raw kibana_url)
curl -u "elastic:<password>" "$KIBANA_URL/api/snapshot_restore/repositories"

# Or via Kibana: Stack Management → Snapshot and Restore
```

### Scaling the cluster

Change `count` in the `nodeSets` block in `eck.tf` and re-apply. With hard anti-affinity
set, each ES pod requires its own AKS node — scale the node pool (`max_count` in `aks.tf`)
before scaling ES, or pods will remain pending.

### Troubleshooting TLS certificate issuance

If Kibana returns a cert error on first deploy, check ACME challenge status:

```bash
kubectl describe certificate -n elastic-system
kubectl describe certificaterequest -n elastic-system
kubectl logs -n cert-manager deployment/cert-manager -f
```

The most common cause is DNS not yet propagated from Cloudflare to Azure DNS. Wait a few
minutes and describe again — cert-manager retries automatically.

## Teardown

```bash
cd infra && terraform destroy
```

---

## Production Readiness

The settings below implement some best practices for ECK in production. 

### 1. vm.max_map_count

Elasticsearch requires `vm.max_map_count=1048576` for mmap-based index access. A privileged
init container sets this on each node before the ES process starts. The quickstart default
`node.store.allow_mmap: false` has been removed.

```yaml
initContainers:
- name: sysctl
  securityContext:
    privileged: true
    runAsUser: 0
  command: [sh, -c, "sysctl -w vm.max_map_count=1048576"]
```

### 2. Compute resources — Guaranteed QoS

Requests equal limits on all ES pods (`4Gi` / `2` CPU). Kubernetes assigns `Guaranteed` QoS
class, preventing eviction under node memory pressure and giving the JVM a stable heap.
The JVM heap is automatically sized to ~2Gi (50 % of the 4Gi memory limit) by ECK.

Setting requests = limits also makes `node.processors` deterministic (derived from CPU limit),
which controls thread pool sizing.

### 3. Persistent storage (volumeClaimTemplates)

Each ES node gets a dedicated 50Gi `ReadWriteOnce` PVC backed by the default AKS storage
class (Azure Premium SSD). PVCs are named `elasticsearch-data` exactly as required by ECK.

The `volumeClaimDeletePolicy` defaults to `DeleteOnScaledownAndClusterDeletion`, meaning
PVCs are cleaned up on scale-down. Change to `DeleteOnScaledownOnly` if you need to recover
data after a cluster delete.

### 4. Pod anti-affinity

Hard anti-affinity (`requiredDuringSchedulingIgnoredDuringExecution`) on
`kubernetes.io/hostname` ensures each ES pod runs on a distinct AKS node. If fewer than
3 nodes are available the scheduler will leave pods pending rather than co-locate them.

```yaml
affinity:
  podAntiAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:
    - labelSelector:
        matchLabels:
          elasticsearch.k8s.elastic.co/cluster-name: elasticsearch
      topologyKey: kubernetes.io/hostname
```

### 5. Zone awareness

Shard allocation awareness prevents primary and replica shards landing in the same
availability zone. If one zone fails, the cluster can still serve every shard.

Three components work together:

1. **`eck.k8s.elastic.co/downward-node-labels` annotation** — ECK copies the
   `topology.kubernetes.io/zone` node label into each pod annotation.
2. **`ZONE` env var** — reads the annotation via the Kubernetes downward API.
3. **`cluster.routing.allocation.awareness.attributes: k8s_node_name,zone`** — tells
   Elasticsearch to spread shards across zones (and nodes).

A `topologySpreadConstraint` (`whenUnsatisfiable: ScheduleAnyway`) nudges the scheduler
to balance pods across zones without hard-blocking if zone capacity is uneven.

The AKS node pool is configured with `zones = ["1", "2", "3"]` to distribute nodes
across all three West Europe availability zones. **Note**: changing `zones` requires node
pool recreation (`terraform destroy && terraform apply`).

### 6. PodDisruptionBudget

`minAvailable: 2` is embedded in the Elasticsearch spec (`spec.podDisruptionBudget`).
ECK manages this PDB automatically and updates it when the cluster scales. With a
3-node cluster this allows one voluntary disruption (node drain) at a time while
maintaining quorum.

Enterprise licence enables per-role PDBs; on Basic the single cluster-level PDB is used.

### 7. Rolling upgrade control (updateStrategy)

`changeBudget.maxSurge: 1` limits ECK to creating one replacement pod at a time during
rolling upgrades, preventing resource exhaustion on a small node pool. `maxUnavailable: 1`
matches the default and allows progress while keeping two nodes always available.

```yaml
updateStrategy:
  changeBudget:
    maxSurge: 1
    maxUnavailable: 1
```

### 8. PreStop hook

ECK installs a PreStop hook automatically. `PRE_STOP_ADDITIONAL_WAIT_SECONDS=50` gives
in-flight requests time to drain and kube-proxy time to sync endpoint removal before
the ES process shuts down. 50 s covers the default kube-proxy resync interval.

### 9. Snapshots (Azure Blob Storage)

Automated backups via the `repository-azure` plugin (built into Elasticsearch):

**Terraform provisions:**
- `azurerm_storage_account` (`eckonakssnapshots`) — Standard LRS
- `azurerm_storage_container` (`elasticsearch-snapshots`)
- Kubernetes secret `elasticsearch-snapshot-credentials` with account name + key,
  injected into the ES keystore via `spec.secureSettings`

**Post-deploy (`scripts/setup-snapshots.sh`):**
- Registers the `azure-backup` snapshot repository
- Creates the `daily-snapshots` SLM policy: runs at 01:30 daily, retains 5–50
  snapshots with a 30-day expiry

```bash
scripts/setup-snapshots.sh
```

The storage account name `eckonakssnapshots` must be globally unique across Azure.
If the apply fails with a name conflict, set a unique `prefix` variable.
