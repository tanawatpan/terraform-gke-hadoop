resource "kubernetes_service_v1" "spark_master" {
  metadata {
    name      = "spark-master"
    namespace = kubernetes_namespace.hadoop.metadata.0.name
  }

  spec {
    cluster_ip = "None"

    selector = {
      app = "spark-master"
    }

    port {
      port        = 7077
      target_port = 7077
    }
  }

  lifecycle {
    ignore_changes = [
      metadata.0.annotations,
    ]
  }
}

resource "kubernetes_service_v1" "spark_thrift" {
  metadata {
    name      = "spark-thrift"
    namespace = kubernetes_namespace.hadoop.metadata.0.name
  }

  spec {
    port {
      name        = "thrift"
      port        = 10000
      target_port = 10000
    }

    selector = {
      app = "spark-thrift"
    }
  }

  lifecycle {
    ignore_changes = [
      metadata.0.annotations,
    ]
  }
}

resource "kubernetes_service_v1" "spark_master_ui" {
  metadata {
    name      = "spark-master-ui"
    namespace = kubernetes_namespace.hadoop.metadata.0.name
  }

  spec {
    type = "NodePort"

    port {
      port        = 8080
      target_port = 8080
    }

    selector = {
      app = "spark-master"
    }
  }

  lifecycle {
    ignore_changes = [
      metadata.0.annotations,
    ]
  }
}

resource "kubernetes_service_v1" "spark_history" {
  metadata {
    name      = "spark-history"
    namespace = kubernetes_namespace.hadoop.metadata.0.name
  }

  spec {
    type = "NodePort"

    port {
      port        = 18080
      target_port = 18080
    }

    selector = {
      app = "spark-history"
    }
  }

  lifecycle {
    ignore_changes = [
      metadata.0.annotations,
    ]
  }
}

resource "kubernetes_stateful_set_v1" "spark_master" {
  metadata {
    name      = kubernetes_service_v1.spark_master.metadata.0.name
    namespace = kubernetes_namespace.hadoop.metadata.0.name
  }

  spec {
    replicas     = 1
    service_name = kubernetes_service_v1.spark_master.metadata.0.name

    selector {
      match_labels = {
        app = kubernetes_service_v1.spark_master.metadata.0.name
      }
    }

    template {
      metadata {
        labels = {
          app = kubernetes_service_v1.spark_master.metadata.0.name
        }
      }

      spec {
        service_account_name = kubernetes_service_account.storage_admin.metadata.0.name

        container {
          name  = kubernetes_service_v1.spark_master.metadata.0.name
          image = "${local.spark.image_name}:${local.spark.version}"

          env {
            name  = "NODE_TYPE"
            value = "SPARK_MASTER"
          }

          env {
            name  = "SPARK_MASTER_HOSTNAME"
            value = "${kubernetes_service_v1.spark_master.metadata.0.name}-0.${kubernetes_service_v1.spark_master.metadata.0.name}.${kubernetes_service_v1.spark_master.metadata.0.namespace}.svc.cluster.local"
          }

          env {
            name  = "NAMENODE_HOSTNAME"
            value = "${kubernetes_service_v1.namenode.metadata.0.name}-0.${kubernetes_service_v1.namenode.metadata.0.name}.${kubernetes_service_v1.namenode.metadata.0.namespace}.svc.cluster.local"
          }

          env {
            name  = "HIVE_METASTORE_HOSTNAME"
            value = "${kubernetes_service_v1.hive_metastore.metadata.0.name}.${kubernetes_service_v1.hive_metastore.metadata.0.namespace}.svc.cluster.local"
          }

          env {
            name  = "HIVE_WAREHOUSE"
            value = local.hive_metastore.warehouse
          }

          port {
            container_port = 7077
          }

          port {
            container_port = 8080
          }

          readiness_probe {
            http_get {
              path = "/"
              port = "8080"
            }

            initial_delay_seconds = 60
            period_seconds        = 10
          }
        }
      }
    }
  }
}

resource "kubernetes_daemon_set_v1" "spark_worker" {
  metadata {
    name      = "spark-worker"
    namespace = kubernetes_namespace.hadoop.metadata.0.name
  }

  spec {
    selector {
      match_labels = {
        app = "spark-worker"
      }
    }

    template {
      metadata {
        labels = {
          app = "spark-worker"
        }
      }

      spec {
        service_account_name = kubernetes_service_account.storage_admin.metadata.0.name

        node_selector = {
          "cloud.google.com/gke-nodepool" = "primary"
        }

        container {
          name  = "spark-worker"
          image = "${local.spark.image_name}:${local.spark.version}"

          env {
            name  = "NODE_TYPE"
            value = "SPARK_WORKER"
          }

          env {
            name  = "NAMENODE_HOSTNAME"
            value = "${kubernetes_service_v1.namenode.metadata.0.name}-0.${kubernetes_service_v1.namenode.metadata.0.name}.${kubernetes_service_v1.namenode.metadata.0.namespace}.svc.cluster.local"
          }

          env {
            name  = "SPARK_MASTER_HOSTNAME"
            value = "${kubernetes_service_v1.spark_master.metadata.0.name}-0.${kubernetes_service_v1.spark_master.metadata.0.name}.${kubernetes_service_v1.spark_master.metadata.0.namespace}.svc.cluster.local"
          }
        }
      }
    }
  }
}

resource "kubernetes_deployment_v1" "spark_history" {
  metadata {
    name      = "spark-history"
    namespace = kubernetes_namespace.hadoop.metadata.0.name
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "spark-history"
      }
    }

    template {
      metadata {
        labels = {
          app = "spark-history"
        }
      }

      spec {
        container {
          name  = "spark-history"
          image = "${local.spark.image_name}:${local.spark.version}"

          env {
            name  = "NODE_TYPE"
            value = "SPARK_HISTORY"
          }

          env {
            name  = "NAMENODE_HOSTNAME"
            value = "${kubernetes_service_v1.namenode.metadata.0.name}-0.${kubernetes_service_v1.namenode.metadata.0.name}.${kubernetes_service_v1.namenode.metadata.0.namespace}.svc.cluster.local"
          }

          env {
            name  = "SPARK_MASTER_HOSTNAME"
            value = "${kubernetes_service_v1.spark_master.metadata.0.name}-0.${kubernetes_service_v1.spark_master.metadata.0.name}.${kubernetes_service_v1.spark_master.metadata.0.namespace}.svc.cluster.local"
          }

          port {
            container_port = 18080
          }

          readiness_probe {
            http_get {
              path = "/"
              port = "18080"
            }

            initial_delay_seconds = 60
            period_seconds        = 10
          }
        }
      }
    }
  }
}

resource "kubernetes_deployment_v1" "spark_thrift" {
  metadata {
    name      = "spark-thrift"
    namespace = kubernetes_namespace.hadoop.metadata.0.name
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "spark-thrift"
      }
    }

    template {
      metadata {
        labels = {
          app = "spark-thrift"
        }
      }

      spec {
        service_account_name = kubernetes_service_account.storage_admin.metadata.0.name

        container {
          name  = "spark-thrift"
          image = "${local.spark.image_name}:${local.spark.version}"

          env {
            name  = "NODE_TYPE"
            value = "SPARK_THRIFT"
          }

          env {
            name  = "NAMENODE_HOSTNAME"
            value = "${kubernetes_service_v1.namenode.metadata.0.name}-0.${kubernetes_service_v1.namenode.metadata.0.name}.${kubernetes_service_v1.namenode.metadata.0.namespace}.svc.cluster.local"
          }

          env {
            name  = "SPARK_MASTER_HOSTNAME"
            value = "${kubernetes_service_v1.spark_master.metadata.0.name}-0.${kubernetes_service_v1.spark_master.metadata.0.name}.${kubernetes_service_v1.spark_master.metadata.0.namespace}.svc.cluster.local"
          }

          env {
            name  = "HIVE_METASTORE_HOSTNAME"
            value = "${kubernetes_service_v1.hive_metastore.metadata.0.name}.${kubernetes_service_v1.hive_metastore.metadata.0.namespace}.svc.cluster.local"
          }

          env {
            name  = "HIVE_WAREHOUSE"
            value = local.hive_metastore.warehouse
          }

          port {
            container_port = 10000
          }
        }
      }
    }
  }
}
