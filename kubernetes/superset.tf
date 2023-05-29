data "http" "superset_values_yaml" {
  url = "https://raw.githubusercontent.com/apache/superset/master/helm/superset/values.yaml"
}

resource "helm_release" "superset" {
  name             = "superset"
  repository       = "http://apache.github.io/superset"
  chart            = "superset"
  namespace        = kubernetes_namespace.hadoop.metadata.0.name
  create_namespace = false

  values = [
    data.http.superset_values_yaml.response_body,
    <<-EOL
		extraConfigs:
		  import_datasources.yaml: |
		    databases:
		    - allow_file_upload: true
		      database_name: "Trino Hive"
		      sqlalchemy_uri: "trino://${local.hadoop.user}@trino.${helm_release.trino.namespace}.svc.cluster.local:8080/hive"
		      expose_in_sqllab: true
		      allow_dml: false
		    - allow_file_upload: false
		      database_name: "Apache Drill"
		      sqlalchemy_uri: "drill+sadrill://${kubernetes_service_v1.drill_service.metadata.0.name}.${kubernetes_service_v1.drill_service.metadata.0.namespace}.svc.cluster.local:8047/dfs?use_ssl=False"
		      expose_in_sqllab: true
		      allow_dml: false
		    - allow_file_upload: false
		      database_name: "Apache Spark SQL"
		      sqlalchemy_uri: "hive://${local.hadoop.user}@${kubernetes_service_v1.spark_thrift.metadata.0.name}.${kubernetes_service_v1.spark_thrift.metadata.0.namespace}.svc.cluster.local:${kubernetes_service_v1.spark_thrift.spec.0.port.0.target_port}"
		      expose_in_sqllab: true
		      allow_dml: false
		service:
		  type: NodePort
		  port: 8088
		  nodePort:
		    http: 32000
		init:
		  adminUser:
		    username: admin
		    password: "${var.superset_password}"
		nodeSelector:
		  "cloud.google.com/gke-nodepool": "secondary"
	EOL
  ]

  set {
    name  = "bootstrapScript"
    value = <<-EOT
		#!/bin/bash
		set -x
		pip3 install pyodbc JPype1
		pip3 install sqlalchemy-drill sqlalchemy-trino pyhive

		sed -i "s/name = b'hive'/name = 'hive'/" $(find /usr/local/lib/ -type d -name 'python3.*' | head -n 1 )/site-packages/pyhive/sqlalchemy_hive.py				# apache/superset#22316
		sed -i "s/driver = b'thrift'/driver = 'thrift'/" $(find /usr/local/lib/ -type d -name 'python3.*' | head -n 1 )/site-packages/pyhive/sqlalchemy_hive.py		# apache/superset#22316
	EOT
  }

  cleanup_on_fail = true
  wait_for_jobs   = true
  timeout         = 600
}
