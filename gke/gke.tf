resource "google_container_cluster" "cluster" {
  name            = var.cluster_name
  location        = var.zone
  network         = google_compute_network.vpc.self_link
  subnetwork      = google_compute_subnetwork.subnet.self_link
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
    workload_pool = "${var.project}.svc.id.goog"
  }

  network_policy {
    provider = "PROVIDER_UNSPECIFIED" # CALICO provider overrides datapath_provider setting, leaving Dataplane v2 disabled
    enabled  = false                  # Enabling NetworkPolicy for clusters with DatapathProvider=ADVANCED_DATAPATH is not allowed (yields error)
  }

  datapath_provider     = "ADVANCED_DATAPATH" # This is where Dataplane V2 is enabled.
  enable_shielded_nodes = true

  timeouts {
    create = "30m"
    update = "40m"
    delete = "30m"
  }

  provisioner "local-exec" {
    command = "gcloud container clusters get-credentials ${self.name} --project ${var.project} --zone ${var.zone}"
  }
}

resource "google_container_node_pool" "primary" {
  name       = "primary"
  cluster    = google_container_cluster.cluster.name
  location   = var.zone
  node_count = var.primary_node_count

  node_config {
    spot         = true
    machine_type = var.primary_machine_type
    disk_size_gb = var.primary_disk_size_gb
    disk_type    = "pd-balanced"

    dynamic "guest_accelerator" {
      for_each = var.primary_gpu_count > 0 ? [1] : []
      content {
        type  = var.primary_gpu_type
        count = var.primary_gpu_count
      }
    }

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
    max_surge       = 0
    max_unavailable = 1
  }

  lifecycle {
    replace_triggered_by = [
      google_container_cluster.cluster.id
    ]
  }
}


resource "google_container_node_pool" "secondary" {
  name       = "secondary"
  cluster    = google_container_cluster.cluster.name
  location   = var.zone
  node_count = var.secondary_node_count

  node_config {
    spot         = true
    machine_type = var.secondary_machine_type
    disk_size_gb = var.secondary_disk_size_gb
    disk_type    = "pd-balanced"

    dynamic "guest_accelerator" {
      for_each = var.secondary_gpu_count > 0 ? [1] : []
      content {
        type  = var.secondary_gpu_type
        count = var.secondary_gpu_count
      }
    }

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
    max_surge       = 0
    max_unavailable = 1
  }

  lifecycle {
    replace_triggered_by = [
      google_container_cluster.cluster.id
    ]
  }
}
