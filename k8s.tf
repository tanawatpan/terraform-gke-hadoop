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
  metadata {
    name = "hadoop"
  }
}
