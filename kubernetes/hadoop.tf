resource "kubernetes_namespace" "hadoop" {
  metadata {
    name = "hadoop"
  }

  timeouts {
    delete = "15m"
  }
}

resource "kubernetes_service_v1" "namenode" {
  metadata {
    name      = "namenode"
    namespace = kubernetes_namespace.hadoop.metadata.0.name
  }

  spec {
    selector = {
      app = "namenode"
    }
    cluster_ip = "None"
  }

  lifecycle {
    ignore_changes = [
      metadata.0.annotations,
    ]
  }
}

resource "kubernetes_service" "datanode" {
  metadata {
    name      = "datanode"
    namespace = kubernetes_namespace.hadoop.metadata.0.name
  }

  spec {
    selector = {
      app = "datanode"
    }
    cluster_ip = "None"
  }

  lifecycle {
    ignore_changes = [
      metadata.0.annotations,
    ]
  }
}


resource "kubernetes_service_v1" "namenode_ui" {
  metadata {
    name      = "namenode-ui"
    namespace = kubernetes_namespace.hadoop.metadata.0.name
  }

  spec {
    type = "NodePort"

    port {
      port        = 9870
      target_port = 9870
    }

    selector = {
      app = "namenode"
    }
  }

  lifecycle {
    ignore_changes = [
      metadata.0.annotations,
    ]
  }
}


resource "kubernetes_stateful_set" "namenode" {
  metadata {
    name      = "namenode"
    namespace = kubernetes_namespace.hadoop.metadata.0.name
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "namenode"
      }
    }

    service_name = "namenode"

    template {
      metadata {
        labels = {
          app = "namenode"
        }
      }

      spec {
        init_container {
          name  = "change-volume-owner"
          image = "busybox:latest"

          command = [
            "/bin/sh",
            "-c",
            "rm -rf /data/lost+found && chown -R 1000:1000 /data",
          ]

          volume_mount {
            mount_path = "/data"
            name       = "namenode-data"
          }
        }

        container {
          name  = "namenode"
          image = "${local.hadoop.image.name}:${local.hadoop.image.tag}"

          env {
            name  = "NODE_TYPE"
            value = "NAMENODE"
          }

          env {
            name  = "NAMENODE_HOSTNAME"
            value = "namenode-0.${kubernetes_service_v1.namenode.metadata.0.name}.${kubernetes_namespace.hadoop.metadata.0.name}.svc.cluster.local"
          }

          port {
            container_port = 9870
          }

          readiness_probe {
            http_get {
              path = "/index.html"
              port = "9870"
            }

            initial_delay_seconds = 60
            period_seconds        = 10
          }

          volume_mount {
            mount_path = "/data"
            name       = "namenode-data"
          }
        }
      }
    }

    volume_claim_template {
      metadata {
        name = "namenode-data"
      }

      spec {
        access_modes = ["ReadWriteOnce"]

        resources {
          requests = {
            storage = "5Gi"
          }
        }

        storage_class_name = "standard-rwo"
      }
    }
  }
}

resource "kubernetes_stateful_set" "datanode" {
  metadata {
    name      = "datanode"
    namespace = kubernetes_namespace.hadoop.metadata.0.name
  }

  spec {
    replicas = 2

    selector {
      match_labels = {
        app = "datanode"
      }
    }

    service_name = "datanode"

    template {
      metadata {
        labels = {
          app = "datanode"
        }
      }

      spec {
        init_container {
          name  = "change-volume-owner"
          image = "busybox:latest"

          command = [
            "/bin/sh",
            "-c",
            "rm -rf /data/lost+found && chown -R 1000:1000 /data",
          ]

          volume_mount {
            mount_path = "/data"
            name       = "datanode-data"
          }
        }

        container {
          name  = "datanode"
          image = "${local.hadoop.image.name}:${local.hadoop.image.tag}"

          env {
            name  = "NODE_TYPE"
            value = "DATANODE"
          }

          env {
            name  = "NAMENODE_HOSTNAME"
            value = "namenode-0.${kubernetes_service_v1.namenode.metadata.0.name}.${kubernetes_namespace.hadoop.metadata.0.name}.svc.cluster.local"
          }

          volume_mount {
            mount_path = "/data"
            name       = "datanode-data"
          }
        }
      }
    }

    volume_claim_template {
      metadata {
        name = "datanode-data"
      }

      spec {
        access_modes = ["ReadWriteOnce"]

        resources {
          requests = {
            storage = "5Gi"
          }
        }

        storage_class_name = "standard-rwo"
      }
    }
  }
}
