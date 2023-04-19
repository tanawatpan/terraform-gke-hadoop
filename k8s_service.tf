resource "kubernetes_service_v1" "namenode" {
  metadata {
    name      = "namenode"
    namespace = kubernetes_namespace.hadoop.metadata.0.name
  }

  spec {
    port {
      port        = 9000
      target_port = 9000
    }

    selector = {
      app = "namenode"
    }
  }
}

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
}

# Spark Master UI Service
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
}

# HDFS Service
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
}

# Spark History Service
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
}

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
}
