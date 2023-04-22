resource "google_container_cluster" "hadoop" {
  name            = local.cluster_name
  location        = var.zone
  network         = google_compute_network.hadoop_gke.self_link
  subnetwork      = google_compute_subnetwork.hadoop_gke.self_link
  networking_mode = "VPC_NATIVE"

  initial_node_count       = 1
  remove_default_node_pool = true

  private_cluster_config {
    enable_private_nodes   = true
    master_ipv4_cidr_block = "172.16.0.32/28"
  }

  ip_allocation_policy {
    cluster_ipv4_cidr_block  = "10.0.0.0/14"
    services_ipv4_cidr_block = "10.4.0.0/20"
  }

  addons_config {
    horizontal_pod_autoscaling {
      disabled = false
    }
    http_load_balancing {
      disabled = false
    }
    gce_persistent_disk_csi_driver_config {
      enabled = true
    }
  }

  maintenance_policy {
    daily_maintenance_window {
      start_time = "03:00"
    }
  }

  release_channel {
    channel = "RAPID"
  }

  workload_identity_config {
    workload_pool = null
  }

  network_policy {
    provider = "PROVIDER_UNSPECIFIED" # CALICO provider overrides datapath_provider setting, leaving Dataplane v2 disabled
    enabled  = false                  # Enabling NetworkPolicy for clusters with DatapathProvider=ADVANCED_DATAPATH is not allowed (yields error)
  }

  datapath_provider     = "ADVANCED_DATAPATH" # This is where Dataplane V2 is enabled.
  enable_shielded_nodes = true

  provisioner "local-exec" {
    command = "gcloud container clusters get-credentials ${self.name}"
  }

  timeouts {
    create = "30m"
    update = "40m"
    delete = "30m"
  }
}

resource "google_container_node_pool" "hadoop_node_pool" {
  name       = "hadoop-node-pool"
  cluster    = google_container_cluster.hadoop.name
  location   = var.zone
  node_count = 4

  node_config {
    preemptible  = true
    machine_type = "n1-standard-2"
    disk_size_gb = 20
    disk_type    = "pd-balanced"

    metadata = {
      disable-legacy-endpoints = "true"
    }

    oauth_scopes = [
      "https://www.googleapis.com/auth/devstorage.read_write",
      "https://www.googleapis.com/auth/logging.write",
      "https://www.googleapis.com/auth/monitoring",
      "https://www.googleapis.com/auth/servicecontrol",
      "https://www.googleapis.com/auth/service.management.readonly",
      "https://www.googleapis.com/auth/trace.append",
    ]
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  upgrade_settings {
    max_surge       = 1
    max_unavailable = 0
  }

  lifecycle {
    replace_triggered_by = [
      google_container_cluster.hadoop.id
    ]
  }
}
