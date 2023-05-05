output "spark_thrift_server" {
  value = "${kubernetes_service_v1.spark_thrift.metadata.0.name}.${kubernetes_namespace.hadoop.metadata.0.name}.svc.cluster.local:${kubernetes_service_v1.spark_thrift.spec.0.port.0.target_port}"
}

output "hive_metastore" {
  value = "${kubernetes_service_v1.hive_metastore.metadata.0.name}.${kubernetes_namespace.hive_metastore.metadata.0.name}.svc.cluster.local:${kubernetes_service_v1.hive_metastore.spec.0.port.0.target_port}"
}

output "namenode" {
  value = "${kubernetes_service_v1.namenode.metadata.0.name}-0.${kubernetes_service_v1.namenode.metadata.0.name}.${kubernetes_namespace.hadoop.metadata.0.name}.svc.cluster.local:${kubernetes_service_v1.namenode.spec.0.port.0.target_port}"
}

output "trino" {
  value = "trino.${helm_release.trino.namespace}.svc.cluster.local:8080"
}

output "drill" {
  value = "${kubernetes_service_v1.drill_service.metadata.0.name}.drill.svc.cluster.local:${kubernetes_service_v1.drill_service.spec.0.port.0.target_port}"
}
