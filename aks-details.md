# AKS Cluster — Pod Reference

## app-routing-system

| Pod | What it does |
|-----|-------------|
| `nginx-*` (x2) | Nginx ingress controller managed by the AKS App Routing addon. Receives all inbound HTTPS traffic on the public load balancer IP, terminates TLS (using the Let's Encrypt cert issued by cert-manager), and forwards requests to the correct backend service. Two replicas for availability. |

## cert-manager

| Pod | What it does |
|-----|-------------|
| `cert-manager-*` | The main controller. Watches `Certificate` resources and drives the ACME challenge flow against Let's Encrypt to obtain and renew TLS certificates. |
| `cert-manager-cainjector-*` | Injects the CA bundle into Kubernetes webhook configurations and CRDs so that admission webhooks can be trusted cluster-wide. |
| `cert-manager-webhook-*` | A Kubernetes admission webhook that validates and mutates cert-manager resource manifests (e.g. rejects invalid `Certificate` or `Issuer` specs) before they are persisted. |

## elastic-system

| Pod | What it does |
|-----|-------------|
| `elastic-operator-0` | The ECK operator. Watches Elasticsearch, Kibana, and other Elastic CRDs and reconciles the desired state — rolling upgrades, scaling, certificate rotation, keystore injection. Runs as a StatefulSet with a single replica. |
| `elasticsearch-es-default-0/1/2` | The 3-node Elasticsearch cluster. Each node holds all roles: master-eligible (cluster coordination and metadata), data_hot (primary index storage), data_content (content tier), and ingest (pipeline processing). One pod per AKS node, spread across availability zones. |
| `kibana-kb-*` | The Kibana instance. Provides the web UI for search, dashboards, and Elastic Stack management. Connects to Elasticsearch via the ECK-managed internal service. |

## kube-system — Azure Monitor (Managed Prometheus)

| Pod | What it does |
|-----|-------------|
| `ama-metrics-*` (x2 Deployment) | Azure Monitor Agent — the Managed Prometheus collection engine. Scrapes Prometheus endpoints across the cluster and forwards metrics to the Azure Monitor Workspace. |
| `ama-metrics-ksm-*` | kube-state-metrics sidecar. Exposes Kubernetes object state (Deployment replicas, Pod phases, node conditions, etc.) as Prometheus metrics for ama-metrics to scrape. |
| `ama-metrics-node-*` (DaemonSet, x4) | Node-level metrics collector. One pod per node; scrapes cAdvisor and node-exporter style metrics from the underlying VM. |
| `ama-metrics-operator-targets-*` | Manages the scrape target configuration for the metrics operator — reads `PodMonitor` and `ServiceMonitor` CRDs and syncs them to the collection config. |

## kube-system — Networking

| Pod | What it does |
|-----|-------------|
| `azure-cns-*` (DaemonSet, x4) | Azure Container Networking Service. Manages pod IP address allocation from the VNet subnet (Azure CNI), enforces network policies, and handles IP recycling. One pod per node. |
| `azure-ip-masq-agent-*` (DaemonSet, x4) | Applies IP masquerade (SNAT) rules on each node so that pod traffic leaving the cluster subnet is translated to the node IP, ensuring return packets route correctly. |
| `cloud-node-manager-*` (DaemonSet, x4) | Handles Azure-specific node lifecycle: attaches the correct route table entries, syncs node labels with Azure VM metadata, and applies cloud taints (e.g. `node.cloudprovider.kubernetes.io/uninitialized`). |
| `kube-proxy-*` (DaemonSet, x4) | Maintains `iptables`/`ipvs` rules on each node that implement Kubernetes `Service` load balancing — translating ClusterIP and NodePort addresses to actual pod IPs. |
| `konnectivity-agent-*` (x2) | Provides the network tunnel between the AKS managed control plane (hosted by Microsoft) and the data plane nodes. Required because the API server runs outside the cluster VNet. |
| `konnectivity-agent-autoscaler-*` | Scales konnectivity agent replicas proportionally to cluster size to maintain API server throughput. |
| `retina-agent-*` (DaemonSet, x4) | Azure Retina eBPF-based network observability agent. Captures network flow telemetry at the kernel level with near-zero overhead and exposes connection-level metrics (latency, drops, DNS) for each node. |

## kube-system — DNS

| Pod | What it does |
|-----|-------------|
| `coredns-*` (x2) | The cluster DNS server. Resolves `<service>.<namespace>.svc.cluster.local` names to ClusterIPs, enabling service discovery between pods. Two replicas for availability. |
| `coredns-autoscaler-*` | Scales CoreDNS replica count based on the number of nodes and cores in the cluster to keep DNS response times stable as the cluster grows. |

## kube-system — Storage (CSI Drivers)

| Pod | What it does |
|-----|-------------|
| `csi-azuredisk-node-*` (DaemonSet, x4) | Azure Disk CSI driver node plugin. Handles attach/detach and mount/unmount of Azure Premium SSD `ReadWriteOnce` PersistentVolumes on each node — used by Elasticsearch data volumes. |
| `csi-azurefile-node-*` (DaemonSet, x4) | Azure Files CSI driver node plugin. Handles mount/unmount of Azure Files `ReadWriteMany` PersistentVolumes. Not used by this deployment but present as a standard AKS component. |

## kube-system — Metrics API

| Pod | What it does |
|-----|-------------|
| `metrics-server-*` (x2) | Aggregates CPU and memory usage metrics from kubelets across all nodes. Used by `kubectl top`, Horizontal Pod Autoscaler, and the cluster autoscaler. Two replicas for availability. |
