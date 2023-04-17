resource "google_compute_network" "hadoop_gke" {
  name                    = "hadoop-gke"
  auto_create_subnetworks = false
}

# Create a subnet for the VPC
resource "google_compute_subnetwork" "hadoop_gke" {
  name          = "hadoop-gke"
  network       = google_compute_network.hadoop_gke.self_link
  ip_cidr_range = "10.0.0.0/28"
}
