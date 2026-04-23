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
        spec:
          version: ${var.elastic_version}
          nodeSets:
          - name: default
            count: 3
            config:
              node.store.allow_mmap: false
            podTemplate:
              spec:
                containers:
                - name: elasticsearch
                  resources:
                    requests:
                      memory: "2Gi"
                      cpu: "1"
                    limits:
                      memory: "2Gi"
        YAML
    }
    command = "echo \"$MANIFEST\" | kubectl apply -f -"
  }

  depends_on = [null_resource.wait_for_eck_operator]
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

