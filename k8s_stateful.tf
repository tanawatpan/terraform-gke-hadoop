
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
          image = "${local.image.name}:${local.image.tag}"

          env {
            name  = "NODE_TYPE"
            value = "DATANODE"
          }

          env {
            name  = "NAMENODE_HOSTNAME"
            value = kubernetes_service_v1.namenode.metadata.0.name
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

resource "kubernetes_stateful_set" "jupyter" {
  depends_on = [google_compute_router_nat.nat]
  metadata {
    name      = "jupyter"
    namespace = kubernetes_namespace.hadoop.metadata.0.name
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "jupyter"
      }
    }

    service_name = "jupyter"

    template {
      metadata {
        labels = {
          app = "jupyter"
        }
      }

      spec {
        init_container {
          name  = "change-volume-owner"
          image = "busybox:latest"

          command = [
            "/bin/sh",
            "-c",
            "rm -rf /home/hadoop/lost+found && chown -R 1000:100 /home/hadoop",
          ]

          volume_mount {
            mount_path = "/home/hadoop"
            name       = "jupyter-notebook"
          }
        }

        container {
          name  = "jupyter"
          image = "jupyter/pyspark-notebook:hadoop-3"

          working_dir = "/home/hadoop"

          security_context {
            run_as_user  = 0
            run_as_group = 0
          }

          env {
            name  = "NB_USER"
            value = "hadoop"
          }

          env {
            name  = "CHOWN_HOME"
            value = "yes"
          }

          env {
            name  = "NOTEBOOK_ARGS"
            value = "--NotebookApp.ip='0.0.0.0' --NotebookApp.port=8888 --NotebookApp.open_browser=False --NotebookApp.token='P@ssw0rd' --NotebookApp.allow_origin='*'"
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
            container_port = 8888
          }

          readiness_probe {
            http_get {
              path = "/login"
              port = "8888"
            }

            initial_delay_seconds = 60
            period_seconds        = 10
          }

          volume_mount {
            mount_path = "/home/hadoop"
            name       = "jupyter-notebook"
          }
        }
      }
    }

    volume_claim_template {
      metadata {
        name = "jupyter-notebook"
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