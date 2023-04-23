provider "tls" {}

provider "http" {}

provider "google" {
  project = var.project
  region  = var.region
  zone    = var.zone
}

data "google_client_config" "provider" {}

data "google_container_cluster" "hadoop" {
  name     = local.cluster_name
  location = var.zone
}

provider "kubernetes" {
  host  = "https://${data.google_container_cluster.hadoop.endpoint}"
  token = data.google_client_config.provider.access_token
  cluster_ca_certificate = base64decode(
    data.google_container_cluster.hadoop.master_auth[0].cluster_ca_certificate,
  )
}

provider "kubectl" {
  host  = "https://${data.google_container_cluster.hadoop.endpoint}"
  token = data.google_client_config.provider.access_token
  cluster_ca_certificate = base64decode(
    data.google_container_cluster.hadoop.master_auth[0].cluster_ca_certificate,
  )
  load_config_file = false
}

provider "helm" {
  kubernetes {
    host  = "https://${data.google_container_cluster.hadoop.endpoint}"
    token = data.google_client_config.provider.access_token
    cluster_ca_certificate = base64decode(
      data.google_container_cluster.hadoop.master_auth[0].cluster_ca_certificate,
    )
  }
}
