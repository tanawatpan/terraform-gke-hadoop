# Create VPC
resource "google_compute_network" "vpc" {
  name                    = "gke-vpc"
  auto_create_subnetworks = false
}

# Create a subnet for the VPC
resource "google_compute_subnetwork" "subnet" {
  name          = "gke-subnet"
  network       = google_compute_network.vpc.self_link
  ip_cidr_range = "192.168.0.0/28"
}

# Cloud Router
resource "google_compute_router" "router" {
  name    = "cloud-router-1"
  network = google_compute_network.vpc.self_link
}

# Cloud NAT
resource "google_compute_router_nat" "nat" {
  name                               = "cloud-nat-1"
  router                             = google_compute_router.router.name
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  log_config {
    enable = false
    filter = "ERRORS_ONLY"
  }
}
