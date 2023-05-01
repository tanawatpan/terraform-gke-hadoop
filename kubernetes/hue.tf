data "http" "hue_values_yaml" {
  url = "https://raw.githubusercontent.com/cloudera/hue/master/tools/kubernetes/helm/hue/values.yaml"
}

resource "helm_release" "hue" {
  name             = "hue"
  repository       = "https://helm.gethue.com"
  chart            = "hue"
  namespace        = kubernetes_namespace.hadoop.metadata.0.name
  create_namespace = true

  values = [
    data.http.hue_values_yaml.response_body,
    <<-EOL
		hue:
		  ini: |
		    [desktop]
		    default_hdfs_superuser=hadoop
		    app_blacklist=search,hbase,security,jobbrowser,oozie,importer
		    django_debug_mode=false
		    [[task_server]]
		    enabled=true
		    broker_url=redis://redis:6379/0
		    result_cache='{"BACKEND": "django_redis.cache.RedisCache", "LOCATION": "redis://redis:6379/0", "OPTIONS": {"CLIENT_CLASS": "django_redis.client.DefaultClient"},"KEY_PREFIX": "queries"}'
		    celery_result_backend=redis://redis:6379/0
		    [hadoop]
		    [[hdfs_clusters]]
		    [[[default]]]
		    fs_defaultfs=hdfs://namenode-0.${kubernetes_service_v1.namenode.metadata.0.name}.${kubernetes_namespace.hadoop.metadata.0.name}.svc.cluster.local:9000
		    webhdfs_url=http://namenode-0.${kubernetes_service_v1.namenode.metadata.0.name}.${kubernetes_namespace.hadoop.metadata.0.name}.svc.cluster.local:9870/webhdfs/v1
		    [spark]
		    sql_server_host=${kubernetes_service_v1.spark_thrift.metadata.0.name}.${kubernetes_namespace.hadoop.metadata.0.name}.svc.cluster.local
		    sql_server_port=10000
	EOL
  ]

  set {
    name  = "hue.interpreters"
    value = <<-EOL
		[[[presto]]]
		name = Trino Hive
		interface=sqlalchemy
		options='{"url": "trino://hadoop@trino.${helm_release.trino.namespace}.svc.cluster.local:8080/hive"}'

		[[[sparksql]]]
		name=Spark SQL
		interface=hiveserver2
	EOL
  }

  set {
    name  = "image.registry"
    value = dirname(local.hue.image.name)
  }

  set {
    name  = "image.tag"
    value = "4.11.0"
  }

  set {
    name  = "workers.enabled"
    value = "true"
  }

  set {
    name  = "balancer.enabled"
    value = "false"
  }

  set {
    name  = "hue.database.persist"
    value = "false"
  }

  set {
    name  = "hue.replicas"
    value = "1"
  }

  cleanup_on_fail = true
  wait_for_jobs   = true
  timeout         = 600
}
