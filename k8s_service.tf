resource "kubernetes_service" "namenode" {
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

resource "kubernetes_service" "spark_master" {
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

resource "kubernetes_service" "namenode_ui" {
  metadata {
    name      = "namenode-ui"
    namespace = kubernetes_namespace.hadoop.metadata.0.name
  }

  spec {
    type = "LoadBalancer"

    port {
      port        = 9870
      target_port = 9870
    }

    selector = {
      app = "namenode"
    }
  }
}

resource "kubernetes_service" "spark_master_ui" {
  metadata {
    name      = "spark-master-ui"
    namespace = kubernetes_namespace.hadoop.metadata.0.name
  }

  spec {
    type = "LoadBalancer"

    port {
      port        = 8080
      target_port = 8080
    }

    selector = {
      app = "spark-master"
    }
  }
}

resource "kubernetes_service" "spark_history" {
  metadata {
    name      = "spark-history"
    namespace = kubernetes_namespace.hadoop.metadata.0.name
  }

  spec {
    type = "LoadBalancer"

    port {
      port        = 18080
      target_port = 18080
    }

    selector = {
      app = "spark-history"
    }
  }
}
