resource "google_compute_global_address" "lb_ip" {
  name         = "lb-ip"
  address_type = "EXTERNAL"
  ip_version   = "IPV4"
}

resource "kubectl_manifest" "frontend_https_redirect" {
  yaml_body = yamlencode({
    apiVersion = "networking.gke.io/v1beta1"
    kind       = "FrontendConfig"
    metadata = {
      name      = "frontend-https-redirect"
      namespace = kubernetes_namespace.hadoop.metadata.0.name
    }
    spec = {
      redirectToHttps = {
        enabled = true
      }
    }
  })
}

resource "kubernetes_ingress_v1" "hadoop_ingress" {
  wait_for_load_balancer = true

  metadata {
    name      = "hadoop-ingress"
    namespace = kubernetes_namespace.hadoop.metadata.0.name
    annotations = {
      "kubernetes.io/ingress.global-static-ip-name" = google_compute_global_address.lb_ip.name
      "ingress.gcp.kubernetes.io/pre-shared-cert"   = google_compute_managed_ssl_certificate.ssl_certificate.name
      "networking.gke.io/v1beta1.FrontendConfig"    = kubectl_manifest.frontend_https_redirect.name
      # "kubernetes.io/ingress.allow-http"            = "false"
    }
  }

  spec {

    rule {
      host = trimsuffix(google_dns_record_set.spark_master.name, ".")

      http {
        path {
          backend {
            service {
              name = kubernetes_service_v1.spark_master_ui.metadata.0.name
              port {
                number = kubernetes_service_v1.spark_master_ui.spec.0.port.0.target_port
              }
            }
          }
        }
      }
    }

    rule {
      host = trimsuffix(google_dns_record_set.namenode.name, ".")

      http {
        path {
          backend {
            service {
              name = kubernetes_service_v1.namenode_ui.metadata.0.name
              port {
                number = kubernetes_service_v1.namenode_ui.spec.0.port.0.target_port
              }
            }
          }
        }
      }
    }

    rule {
      host = trimsuffix(google_dns_record_set.spark_history.name, ".")

      http {
        path {
          backend {
            service {
              name = kubernetes_service_v1.spark_history.metadata.0.name
              port {
                number = kubernetes_service_v1.spark_history.spec.0.port.0.target_port
              }
            }
          }
        }
      }
    }

    rule {
      host = trimsuffix(google_dns_record_set.jupyter.name, ".")

      http {
        path {
          backend {
            service {
              name = kubernetes_service_v1.jupyter.metadata.0.name
              port {
                number = kubernetes_service_v1.jupyter.spec.0.port.0.target_port
              }
            }
          }
        }
      }
    }

    rule {
      host = trimsuffix(google_dns_record_set.superset.name, ".")
      http {
        path {
          backend {
            service {
              name = helm_release.superset.metadata.0.name
              port {
                number = "8088"
              }
            }
          }
        }
      }
    }

    rule {
      host = trimsuffix(google_dns_record_set.hue.name, ".")
      http {
        path {
          backend {
            service {
              name = helm_release.hue.metadata.0.name
              port {
                number = "8888"
              }
            }
          }
        }
      }
    }
  }
}
