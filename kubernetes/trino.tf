data "http" "trino_values_yaml" {
  url = "https://raw.githubusercontent.com/trinodb/charts/main/charts/trino/values.yaml"
}

resource "helm_release" "trino" {
  name             = "trino"
  repository       = "https://trinodb.github.io/charts"
  chart            = "trino"
  namespace        = "trino"
  create_namespace = true

  values = [
    data.http.trino_values_yaml.response_body,
    <<-EOL
		additionalCatalogs:
		  hive: |-
		    connector.name=hive
		    hive.hdfs.impersonation.enabled=true
		    hive.metastore.uri=thrift://${kubernetes_service_v1.hive_metastore.metadata.0.name}.${kubernetes_namespace.hive_metastore.metadata.0.name}.svc.cluster.local:${kubernetes_service_v1.hive_metastore.spec.0.port.0.target_port}
	EOL
  ]

  set {
    name  = "server.workers"
    value = 2
  }

  cleanup_on_fail = true
  wait_for_jobs   = true
  timeout         = 600
}
