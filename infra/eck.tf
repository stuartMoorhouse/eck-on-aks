resource "null_resource" "elasticsearch" {
  triggers = {
    elastic_version = var.elastic_version
  }

  provisioner "local-exec" {
    environment = {
      MANIFEST = <<-YAML
        apiVersion: elasticsearch.k8s.elastic.co/v1
        kind: Elasticsearch
        metadata:
          name: elasticsearch
          namespace: elastic-system
          annotations:
            eck.k8s.elastic.co/downward-node-labels: "topology.kubernetes.io/zone"
        spec:
          version: ${var.elastic_version}
          updateStrategy:
            changeBudget:
              maxSurge: 1
              maxUnavailable: 1
          podDisruptionBudget:
            spec:
              minAvailable: 2
              selector:
                matchLabels:
                  elasticsearch.k8s.elastic.co/cluster-name: elasticsearch
          secureSettings:
          - secretName: elasticsearch-snapshot-credentials
          nodeSets:
          - name: default
            count: 3
            config:
              node.roles: ["master", "data_hot", "data_content", "ingest"]
              node.attr.zone: $${ZONE}
              cluster.routing.allocation.awareness.attributes: k8s_node_name,zone
            podTemplate:
              spec:
                initContainers:
                - name: sysctl
                  securityContext:
                    privileged: true
                    runAsUser: 0
                  command:
                  - sh
                  - -c
                  - sysctl -w vm.max_map_count=1048576
                containers:
                - name: elasticsearch
                  resources:
                    requests:
                      memory: "4Gi"
                      cpu: "2"
                    limits:
                      memory: "4Gi"
                      cpu: "2"
                  env:
                  - name: ZONE
                    valueFrom:
                      fieldRef:
                        fieldPath: metadata.annotations['topology.kubernetes.io/zone']
                  - name: PRE_STOP_ADDITIONAL_WAIT_SECONDS
                    value: "50"
                affinity:
                  podAntiAffinity:
                    requiredDuringSchedulingIgnoredDuringExecution:
                    - labelSelector:
                        matchLabels:
                          elasticsearch.k8s.elastic.co/cluster-name: elasticsearch
                      topologyKey: kubernetes.io/hostname
                topologySpreadConstraints:
                - maxSkew: 1
                  topologyKey: topology.kubernetes.io/zone
                  whenUnsatisfiable: ScheduleAnyway
                  labelSelector:
                    matchLabels:
                      elasticsearch.k8s.elastic.co/cluster-name: elasticsearch
            volumeClaimTemplates:
            - metadata:
                name: elasticsearch-data
              spec:
                accessModes:
                - ReadWriteOnce
                resources:
                  requests:
                    storage: 50Gi
        YAML
    }
    command = "echo \"$MANIFEST\" | kubectl apply -f -"
  }

  depends_on = [
    null_resource.wait_for_eck_operator,
    null_resource.elasticsearch_snapshot_secret,
  ]
}

resource "null_resource" "kibana" {
  triggers = {
    elastic_version = var.elastic_version
  }

  provisioner "local-exec" {
    environment = {
      MANIFEST = <<-YAML
        apiVersion: kibana.k8s.elastic.co/v1
        kind: Kibana
        metadata:
          name: kibana
          namespace: elastic-system
        spec:
          version: ${var.elastic_version}
          count: 1
          elasticsearchRef:
            name: elasticsearch
        YAML
    }
    command = "echo \"$MANIFEST\" | kubectl apply -f -"
  }

  depends_on = [null_resource.elasticsearch]
}
