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
            value = kubernetes_service_v1.namenode.metadata.0.name
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

  lifecycle {
    replace_triggered_by = [
      local_file.dockerfile.id
    ]
  }
}

resource "kubernetes_deployment" "spark_worker" {
  metadata {
    name      = "spark-worker"
    namespace = kubernetes_namespace.hadoop.metadata.0.name
  }

  spec {
    replicas = 2

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
            value = kubernetes_service_v1.namenode.metadata.0.name
          }

          env {
            name  = "SPARK_MASTER_HOSTNAME"
            value = kubernetes_service_v1.spark_master.metadata.0.name
          }
        }
      }
    }
  }

  lifecycle {
    replace_triggered_by = [
      local_file.dockerfile.id
    ]
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
            value = kubernetes_service_v1.namenode.metadata.0.name
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

  lifecycle {
    replace_triggered_by = [
      local_file.dockerfile.id
    ]
  }
}
