resource "kubernetes_service_v1" "jupyter" {
  metadata {
    name      = "jupyter"
    namespace = kubernetes_namespace.hadoop.metadata.0.name
  }

  spec {
    type = "NodePort"

    port {
      port        = 8888
      target_port = 8888
    }

    selector = {
      app = "jupyter"
    }
  }

  lifecycle {
    ignore_changes = [
      metadata.0.annotations,
    ]
  }
}

resource "kubernetes_stateful_set_v1" "jupyter" {
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
        service_account_name = kubernetes_service_account.storage_admin.metadata.0.name

        init_container {
          name  = "change-volume-owner"
          image = "busybox:latest"

          command = [
            "/bin/sh",
            "-c",
            "rm -rf /home/${local.hadoop.user}/jupyter/lost+found && chown -R 1000:1000 /home/${local.hadoop.user}/jupyter",
          ]

          volume_mount {
            mount_path = "/home/${local.hadoop.user}/jupyter"
            name       = "jupyter-notebook"
          }
        }

        container {
          name  = "jupyter"
          image = "${local.jupyter.image_name}:${local.jupyter.version}"

          env {
            name  = "NODE_TYPE"
            value = "JUPYTER"
          }

          env {
            name  = "NAMENODE_HOSTNAME"
            value = "${kubernetes_service_v1.namenode.metadata.0.name}-0.${kubernetes_service_v1.namenode.metadata.0.name}.${kubernetes_service_v1.namenode.metadata.0.namespace}.svc.cluster.local"
          }

          env {
            name  = "SPARK_MASTER_HOSTNAME"
            value = kubernetes_service_v1.spark_master.metadata.0.name
          }

          env {
            name  = "SPARK_DRIVER_MEMORY"
            value = "4g"
          }

          env {
            name  = "HIVE_METASTORE_HOSTNAME"
            value = "${kubernetes_service_v1.hive_metastore.metadata.0.name}.${kubernetes_service_v1.hive_metastore.metadata.0.namespace}.svc.cluster.local"
          }

          env {
            name  = "HIVE_WAREHOUSE"
            value = local.hive_metastore.warehouse
          }

          resources {
            requests = {
              cpu    = "1000m"
              memory = "6Gi"
            }
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
            mount_path = "/home/${local.hadoop.user}/jupyter"
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
