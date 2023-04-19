
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
          image = "busybox"

          command = [
            "/bin/sh",
            "-c",
            "rm -rf /hdfs/namenode/* && chown -R 1000:1000 /hdfs/namenode",
          ]

          volume_mount {
            mount_path = "/hdfs/namenode"
            name       = "namenode-data"
          }
        }

        container {
          name  = "namenode"
          image = "${local.image.name}:${local.image.tag}"

          env {
            name  = "NODE_TYPE"
            value = "NAMENODE"
          }

          env {
            name  = "NAMENODE_HOSTNAME"
            value = "0.0.0.0"
          }

          port {
            container_port = 9870
          }

          volume_mount {
            mount_path = "/hdfs/namenode"
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
          image = "busybox"

          command = [
            "/bin/sh",
            "-c",
            "rm -rf /hdfs/datanode/lost+found && chown -R 1000:1000 /hdfs/datanode",
          ]

          volume_mount {
            mount_path = "/hdfs/datanode"
            name       = "datanode-data"
          }
        }

        container {
          name  = "datanode"
          image = "${local.image.name}:${local.image.tag}"

          env {
            name  = "NODE_TYPE"
            value = "DATANODE"
          }

          env {
            name  = "NAMENODE_HOSTNAME"
            value = kubernetes_service.namenode.metadata.0.name
          }

          volume_mount {
            mount_path = "/hdfs/datanode"
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
