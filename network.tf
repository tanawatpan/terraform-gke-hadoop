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

resource "google_compute_global_address" "lb_ip" {
  name         = "lb-ip"
  address_type = "EXTERNAL"
  ip_version   = "IPV4"
}

resource "google_dns_managed_zone" "dns" {
  name     = replace(var.web_domain, ".", "-")
  dns_name = "${var.web_domain}."
}

resource "google_dns_record_set" "jupyter" {
  name         = "lab.${google_dns_managed_zone.dns.dns_name}"
  type         = "A"
  ttl          = 300
  rrdatas      = [google_compute_global_address.lb_ip.address]
  managed_zone = google_dns_managed_zone.dns.name
}

resource "google_dns_record_set" "spark_history" {
  name         = "spark-history.${google_dns_managed_zone.dns.dns_name}"
  type         = "A"
  ttl          = 300
  rrdatas      = [google_compute_global_address.lb_ip.address]
  managed_zone = google_dns_managed_zone.dns.name
}

resource "google_dns_record_set" "spark_master" {
  name         = "spark-master.${google_dns_managed_zone.dns.dns_name}"
  type         = "A"
  ttl          = 300
  rrdatas      = [google_compute_global_address.lb_ip.address]
  managed_zone = google_dns_managed_zone.dns.name
}

resource "google_dns_record_set" "namenode" {
  name         = "namenode.${google_dns_managed_zone.dns.dns_name}"
  type         = "A"
  ttl          = 300
  rrdatas      = [google_compute_global_address.lb_ip.address]
  managed_zone = google_dns_managed_zone.dns.name
}

resource "google_compute_managed_ssl_certificate" "hadoop_ssl_certificate" {
  name = "hadoop-ssl-certificate"

  managed {
    domains = [google_dns_record_set.jupyter.name, google_dns_record_set.spark_master.name, google_dns_record_set.spark_history.name, google_dns_record_set.namenode.name]
  }
}
