resource "kubernetes_namespace" "hive_metastore" {

  metadata {
    name = "hive-metastore"
  }
}

resource "kubernetes_service_v1" "hive_metastore" {
  metadata {
    name      = "hive-metastore"
    namespace = kubernetes_namespace.hive_metastore.metadata.0.name
  }

  spec {
    port {
      port        = 9083
      target_port = 9083
    }

    selector = {
      app = "hive-metastore"
    }
  }
}

resource "kubernetes_service_v1" "hive_metastore_mysql" {
  metadata {
    name      = "hive-metastore-mysql"
    namespace = kubernetes_namespace.hive_metastore.metadata.0.name
  }

  spec {
    port {
      port        = 3306
      target_port = 3306
    }

    selector = {
      app = "hive-metastore-mysql"
    }
  }
}

resource "kubernetes_deployment" "hive_metastore" {
  metadata {
    name      = "hive-metastore"
    namespace = kubernetes_namespace.hive_metastore.metadata.0.name
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "hive-metastore"
      }
    }

    template {
      metadata {
        labels = {
          app = "hive-metastore"
        }
      }

      spec {
        container {
          name  = "hive-metastore"
          image = "${local.hive_metastore.image.name}:${local.hive_metastore.image.tag}"

          env {
            name  = "NAMENODE_HOSTNAME"
            value = "${kubernetes_service_v1.namenode.metadata.0.name}.${kubernetes_namespace.hadoop.metadata.0.name}.svc.cluster.local"
          }

          env {
            name  = "HIVE_WAREHOUSE"
            value = "/user/hive/warehouse"
          }

          env {
            name  = "DATABASE_HOST"
            value = kubernetes_service_v1.hive_metastore_mysql.metadata.0.name
          }

          env {
            name  = "DATABASE_PORT"
            value = kubernetes_service_v1.hive_metastore_mysql.spec.0.port.0.target_port
          }

          env {
            name  = "DATABASE_DB"
            value = "metastore_db"
          }

          env {
            name  = "DATABASE_USER"
            value = "admin"
          }
          env {
            name  = "DATABASE_PASSWORD"
            value = "admin"
          }

          port {
            container_port = 9083
          }
        }
      }
    }
  }
}

resource "kubernetes_stateful_set" "hive_metastore_mysql" {
  metadata {
    name      = "hive-metastore-mysql"
    namespace = kubernetes_namespace.hive_metastore.metadata.0.name
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "hive-metastore-mysql"
      }
    }

    service_name = "hive-metastore-mysql"

    template {
      metadata {
        labels = {
          app = "hive-metastore-mysql"
        }
      }

      spec {
        init_container {
          name  = "change-volume-owner"
          image = "busybox:latest"

          command = [
            "/bin/sh",
            "-c",
            "rm -rf /var/lib/mysql/lost+found",
          ]

          volume_mount {
            mount_path = "/var/lib/mysql"
            name       = "mysql-data"
          }
        }

        container {
          name  = "hive-metastore-mysql"
          image = "mariadb:latest"

          port {
            container_port = 3306
          }

          env {
            name  = "MYSQL_ROOT_PASSWORD"
            value = "admin"
          }
          env {
            name  = "MYSQL_USER"
            value = "admin"
          }
          env {
            name  = "MYSQL_PASSWORD"
            value = "admin"
          }
          env {
            name  = "MYSQL_DATABASE"
            value = "metastore_db"
          }

          volume_mount {
            mount_path = "/var/lib/mysql"
            name       = "mysql-data"
          }
        }
      }
    }

    volume_claim_template {
      metadata {
        name = "mysql-data"
      }

      spec {
        access_modes = ["ReadWriteOnce"]

        resources {
          requests = {
            storage = "3Gi"
          }
        }

        storage_class_name = "standard-rwo"
      }
    }
  }
}