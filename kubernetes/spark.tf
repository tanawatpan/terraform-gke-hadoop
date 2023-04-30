resource "kubernetes_service_v1" "spark_master" {
  metadata {
    name      = "spark-master"
    namespace = kubernetes_namespace.hadoop.metadata.0.name
  }

  spec {
    port {
      port        = 7077
      target_port = 7077
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

resource "kubernetes_deployment" "spark_master" {
  metadata {
    name      = "spark-master"
    namespace = kubernetes_namespace.hadoop.metadata.0.name
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "spark-master"
      }
    }

    template {
      metadata {
        labels = {
          app = "spark-master"
        }
      }

      spec {
        container {
          name  = "spark-master"
          image = "${local.hadoop.image.name}:${local.hadoop.image.tag}"

          env {
            name  = "NODE_TYPE"
            value = "SPARK_MASTER"
          }

          env {
            name  = "SPARK_MASTER_HOSTNAME"
            value = "0.0.0.0"
          }

          env {
            name  = "NAMENODE_HOSTNAME"
            value = "namenode-0.${kubernetes_service_v1.namenode.metadata.0.name}.${kubernetes_namespace.hadoop.metadata.0.name}.svc.cluster.local"
          }

          env {
            name  = "HIVE_METASTORE_HOSTNAME"
            value = "${kubernetes_service_v1.hive_metastore.metadata.0.name}.${kubernetes_namespace.hive_metastore.metadata.0.name}.svc.cluster.local"
          }

          env {
            name  = "HIVE_WAREHOUSE"
            value = "user/hive/warehouse"
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

resource "kubernetes_deployment" "spark_worker" {
  metadata {
    name      = "spark-worker"
    namespace = kubernetes_namespace.hadoop.metadata.0.name
  }

  spec {
    replicas = 4

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
        container {
          name  = "spark-worker"
          image = "${local.hadoop.image.name}:${local.hadoop.image.tag}"

          env {
            name  = "NODE_TYPE"
            value = "SPARK_WORKER"
          }

          env {
            name  = "NAMENODE_HOSTNAME"
            value = "namenode-0.${kubernetes_service_v1.namenode.metadata.0.name}.${kubernetes_namespace.hadoop.metadata.0.name}.svc.cluster.local"
          }

          env {
            name  = "SPARK_MASTER_HOSTNAME"
            value = kubernetes_service_v1.spark_master.metadata.0.name
          }
        }
      }
    }
  }
}

resource "kubernetes_deployment" "spark_history" {
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
          image = "${local.hadoop.image.name}:${local.hadoop.image.tag}"

          env {
            name  = "NODE_TYPE"
            value = "SPARK_HISTORY"
          }

          env {
            name  = "NAMENODE_HOSTNAME"
            value = "namenode-0.${kubernetes_service_v1.namenode.metadata.0.name}.${kubernetes_namespace.hadoop.metadata.0.name}.svc.cluster.local"
          }

          env {
            name  = "SPARK_MASTER_HOSTNAME"
            value = kubernetes_service_v1.spark_master.metadata.0.name
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

resource "kubernetes_deployment" "spark_thrift" {
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
        container {
          name  = "spark-thrift"
          image = "${local.hadoop.image.name}:${local.hadoop.image.tag}"

          env {
            name  = "NODE_TYPE"
            value = "SPARK_THRIFT"
          }

          env {
            name  = "NAMENODE_HOSTNAME"
            value = "namenode-0.${kubernetes_service_v1.namenode.metadata.0.name}.${kubernetes_namespace.hadoop.metadata.0.name}.svc.cluster.local"
          }

          env {
            name  = "SPARK_MASTER_HOSTNAME"
            value = kubernetes_service_v1.spark_master.metadata.0.name
          }

          env {
            name  = "HIVE_METASTORE_HOSTNAME"
            value = "${kubernetes_service_v1.hive_metastore.metadata.0.name}.${kubernetes_namespace.hive_metastore.metadata.0.name}.svc.cluster.local"
          }

          env {
            name  = "HIVE_WAREHOUSE"
            value = "user/hive/warehouse"
          }

          port {
            container_port = 10000
          }
        }
      }
    }
  }
}
