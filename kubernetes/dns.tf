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

resource "google_dns_record_set" "superset" {
  name         = "superset.${google_dns_managed_zone.dns.dns_name}"
  type         = "A"
  ttl          = 300
  rrdatas      = [google_compute_global_address.lb_ip.address]
  managed_zone = google_dns_managed_zone.dns.name
}

resource "google_dns_record_set" "hue" {
  name         = "hue.${google_dns_managed_zone.dns.dns_name}"
  type         = "A"
  ttl          = 300
  rrdatas      = [google_compute_global_address.lb_ip.address]
  managed_zone = google_dns_managed_zone.dns.name
}

resource "google_compute_managed_ssl_certificate" "ssl_certificate" {
  name = "ssl-certificate"

  managed {
    domains = [google_dns_record_set.jupyter.name, google_dns_record_set.spark_master.name, google_dns_record_set.spark_history.name, google_dns_record_set.namenode.name, google_dns_record_set.superset.name, google_dns_record_set.hue.name]
  }
}
