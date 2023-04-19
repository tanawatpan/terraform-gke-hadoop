resource "google_container_cluster" "hadoop" {
  name               = "hadoop"
  location           = var.zone
  network            = google_compute_network.hadoop_gke.self_link
  subnetwork         = google_compute_subnetwork.hadoop_gke.self_link
  initial_node_count = 3

  remove_default_node_pool = true

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
    channel = "REGULAR"
  }

  enable_shielded_nodes = true

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
  node_count = 3

  node_config {
    preemptible  = true
    machine_type = "n1-standard-2"
    disk_size_gb = 30
    disk_type    = "pd-balanced"
    image_type   = "COS_CONTAINERD"

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
}
