data "http" "trino_values_yaml" {
  url = "https://raw.githubusercontent.com/trinodb/charts/main/charts/trino/values.yaml"
}

resource "helm_release" "trino" {
  name             = "trino"
  repository       = "https://trinodb.github.io/charts"
  chart            = "trino"
  namespace        = "trino"
  create_namespace = true

  values = [data.http.trino_values_yaml.response_body]

  set {
    name  = "server.workers"
    value = 2
  }

  set {
    name  = "additionalCatalogs.hive\\.properties"
    value = <<-EOL
		connector.name=hive
		hive.metastore.uri=thrift://${kubernetes_service_v1.hive_metastore.metadata.0.name}.${kubernetes_namespace.hive_metastore.metadata.0.name}.svc.cluster.local:${kubernetes_service_v1.hive_metastore.spec.0.port.0.target_port}
	EOL
  }

  cleanup_on_fail = true
  wait_for_jobs   = true
  timeout         = 600
}
