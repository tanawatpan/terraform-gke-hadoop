data "google_client_config" "provider" {}

provider "kubernetes" {
  host  = "https://${google_container_cluster.hadoop.endpoint}"
  token = data.google_client_config.provider.access_token
  cluster_ca_certificate = base64decode(
    google_container_cluster.hadoop.master_auth[0].cluster_ca_certificate,
  )
}

provider "kubectl" {
  host  = "https://${google_container_cluster.hadoop.endpoint}"
  token = data.google_client_config.provider.access_token
  cluster_ca_certificate = base64decode(
    google_container_cluster.hadoop.master_auth[0].cluster_ca_certificate,
  )
  load_config_file = false
}

resource "kubernetes_namespace" "hadoop" {
  depends_on = [local_file.dockerfile, local_file.jupyter_dockerfile, google_container_node_pool.hadoop_node_pool]
  metadata {
    name = google_container_cluster.hadoop.name
  }

  lifecycle {
    replace_triggered_by = [
      google_container_cluster.hadoop.id
    ]
  }

  timeouts {
    delete = "15m"
  }
}
