data "http" "trino_values_yaml" {
  url = "https://raw.githubusercontent.com/trinodb/charts/main/charts/trino/values.yaml"
}

resource "helm_release" "trino" {
  name             = "trino"
  repository       = "https://trinodb.github.io/charts"
  chart            = "trino"
  namespace        = kubernetes_namespace.hadoop.metadata.0.name
  create_namespace = false

  values = [
    data.http.trino_values_yaml.response_body,
    <<-EOL
		additionalCatalogs:
		  hive: |-
		    connector.name=hive
		    hive.metastore.username=${local.hadoop.user}
		    hive.hdfs.impersonation.enabled=true
		    hive.auto-purge=true
		    hive.allow-drop-table=true
		    hive.allow-rename-table=true
		    hive.allow-add-column=true
		    hive.allow-drop-column=true
		    hive.allow-rename-column=true
		    hive.metastore.thrift.delete-files-on-drop=true
		    hive.storage-format=PARQUET
		    hive.metastore.uri=thrift://${local.hadoop.user}@${kubernetes_service_v1.hive_metastore.metadata.0.name}.${kubernetes_service_v1.hive_metastore.metadata.0.namespace}.svc.cluster.local:${kubernetes_service_v1.hive_metastore.spec.0.port.0.target_port}
		serviceAccount:
		  create: false
		  name: ${kubernetes_service_account.storage_admin.metadata.0.name}
		coordinator:
		  nodeSelector:
		    "cloud.google.com/gke-nodepool": "primary"
		worker:
		  nodeSelector:
		    "cloud.google.com/gke-nodepool": "primary"
	EOL
  ]

  set {
    name  = "server.workers"
    value = local.trino.worker.replicas
  }

  cleanup_on_fail = true
  wait_for_jobs   = true
  timeout         = 600
}
