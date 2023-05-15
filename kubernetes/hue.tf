data "http" "hue_values_yaml" {
  url = "https://raw.githubusercontent.com/cloudera/hue/master/tools/kubernetes/helm/hue/values.yaml"
}

resource "kubernetes_service_v1" "postgres_hue" {
  metadata {
    name      = "postgres-hue"
    namespace = kubernetes_namespace.hadoop.metadata.0.name
  }

  spec {
    selector = {
      app = "postgres-hue"
    }

    port {
      name = "pgql"
      port = 5432
    }

    type = "ClusterIP"
  }
}

resource "kubernetes_stateful_set_v1" "postgres_hue" {
  metadata {
    name      = "postgres-hue"
    namespace = kubernetes_namespace.hadoop.metadata[0].name
  }

  spec {
    replicas     = 1
    service_name = "postgres-hue"

    selector {
      match_labels = {
        app = "postgres-hue"
      }
    }

    template {
      metadata {
        labels = {
          app = "postgres-hue"
        }
      }

      spec {
        container {
          name  = "postgres-hue"
          image = "postgres:${local.hue.postgres.version}"

          env {
            name  = "POSTGRES_USER"
            value = local.hue.postgres.user
          }

          env {
            name  = "POSTGRES_PASSWORD"
            value = local.hue.postgres.password
          }

          env {
            name  = "POSTGRES_DB"
            value = local.hue.postgres.database
          }

          env {
            name  = "PGDATA"
            value = "/var/lib/postgresql/data/pgdata"
          }

          port {
            container_port = kubernetes_service_v1.postgres_hue.spec.0.port.0.port
            protocol       = "TCP"
          }

          resources {
            requests = {
              cpu = "20m"
            }
          }

          volume_mount {
            mount_path = "/var/lib/postgresql/data"
            name       = "postgres-data"
          }
        }

      }
    }

    volume_claim_template {
      metadata {
        name = "postgres-data"
      }

      spec {
        access_modes = ["ReadWriteOnce"]

        resources {
          requests = {
            storage = "1Gi"
          }
        }

        storage_class_name = "standard-rwo"
      }
    }
  }
}

resource "helm_release" "hue" {
  name             = "hue"
  repository       = "https://helm.gethue.com"
  chart            = "hue"
  namespace        = kubernetes_namespace.hadoop.metadata.0.name
  create_namespace = false

  values = [
    data.http.hue_values_yaml.response_body,
    <<-EOL
		hue:
		  ini: |
		    [desktop]
		    default_hdfs_superuser=${local.hadoop.user}
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
		    fs_defaultfs=hdfs://${kubernetes_service_v1.namenode.metadata.0.name}-0.${kubernetes_service_v1.namenode.metadata.0.name}.${kubernetes_service_v1.namenode.metadata.0.namespace}.svc.cluster.local:${kubernetes_service_v1.namenode.spec.0.port.0.target_port}
		    webhdfs_url=http://${kubernetes_service_v1.namenode.metadata.0.name}-0.${kubernetes_service_v1.namenode.metadata.0.name}.${kubernetes_service_v1.namenode.metadata.0.namespace}.svc.cluster.local:${kubernetes_service_v1.namenode_ui.spec.0.port.0.target_port}/webhdfs/v1
		    [spark]
		    sql_server_host=${kubernetes_service_v1.spark_thrift.metadata.0.name}.${kubernetes_service_v1.spark_thrift.metadata.0.namespace}.svc.cluster.local
		    sql_server_port=${kubernetes_service_v1.spark_thrift.spec.0.port.0.target_port}
		  database:
		    create: false
		    name: "${local.hue.postgres.database}"
		    host: "${local.hue.postgres.hostname}"
		    user: "${local.hue.postgres.user}"
		    port: ${kubernetes_stateful_set_v1.postgres_hue.spec.0.template.0.spec.0.container.0.port.0.container_port}
	EOL
  ]

  set {
    name  = "hue.interpreters"
    value = <<-EOL
		[[[presto]]]
		name = Trino Hive
		interface=sqlalchemy
		options='{"url": "trino://${local.hadoop.user}@trino.${helm_release.trino.namespace}.svc.cluster.local:8080/hive"}'

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
    value = local.hue.image.tag
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
    name  = "hue.replicas"
    value = local.hue.replicas
  }

  set_sensitive {
    name  = "hue.database.password"
    value = local.hue.postgres.password
  }

  cleanup_on_fail = true
  wait_for_jobs   = true
  timeout         = 600
}
