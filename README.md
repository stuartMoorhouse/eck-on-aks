# ECK on AKS

Elastic Cloud on Kubernetes (ECK) deployed on Azure Kubernetes Service (AKS),
managed with Terraform.

## Architecture

- **AKS cluster**: 3 nodes (`Standard_D4s_v3`, 4 vCPU / 16 GB), multi-zone
- **ECK operator**: Manages Elasticsearch, Kibana, Fleet Server, APM Server
- **Elasticsearch**: 3-node cluster, all roles combined (master + data_hot + ingest)
- **DNS**: Azure DNS zone delegated from Cloudflare; `*.eck-on-aks.cascavel-security.net`
- **TLS**: Let's Encrypt via cert-manager + Azure App Routing ingress
- **Snapshots**: Azure Blob Storage, daily SLM policy

## Prerequisites

- Azure CLI (`az login` with access to subscription `YOUR_SUBSCRIPTION_ID`)
- `kubectl`, `terraform`, `helm`
- Cloudflare API token exported as `TF_VAR_cloudflare_zone_id`

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

| Service      | URL                                              |
|--------------|--------------------------------------------------|
| Kibana       | https://kibana.eck-on-aks.cascavel-security.net  |
| Fleet Server | https://fleet.eck-on-aks.cascavel-security.net   |
| APM Server   | https://apm.eck-on-aks.cascavel-security.net     |

## Teardown

```bash
cd infra && terraform destroy
```

---

## Production Readiness

The settings below implement the ECK production checklist. Items marked **not applicable**
are out of scope for this demo deployment (monitoring cluster, Enterprise licence, air-gapped).

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

### Items not implemented

| Item | Reason |
|------|--------|
| Stack Monitoring (dedicated monitoring cluster) | Out of scope for this demo |
| Enterprise licence + autoscaling + per-role PDBs | Licence required |
| Air-gapped / private registry | Not required in this environment |
| Dedicated master nodes (3) + dedicated data nodes (3+) | Implemented — see NodeSets `master` and `data-hot` |
| Custom TLS CA | ECK auto-managed self-signed certs are acceptable here |
