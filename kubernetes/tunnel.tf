resource "kubernetes_namespace" "cloudflare" {
  metadata {
    name = "cloudflare"
  }
}

resource "kubernetes_secret" "cloudflare_secret" {
  metadata {
    name      = "cloudflare-secret"
    namespace = kubernetes_namespace.cloudflare.metadata.0.name
  }

  data = {
    token = base64encode(var.cloudflare_tunnel_token)
  }

  type = "Opaque"
}

resource "kubernetes_deployment" "cloudflare_tunnel" {
  metadata {
    name      = "cloudflare-tunnel"
    namespace = kubernetes_namespace.cloudflare.metadata.0.name
  }

  spec {
    replicas = 1
    selector {
      match_labels = {
        app = "cloudflare-tunnel"
      }
    }

    template {
      metadata {
        labels = {
          app = "cloudflare-tunnel"
        }
      }

      spec {
        container {
          image = "cloudflare/cloudflared:latest"
          name  = "cloudflare-tunnel"

          resources {
            limits = {
              cpu    = "500m"
              memory = "512Mi"
            }
          }

          env {
            name = "CLOUDFLARE_TOKEN"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.cloudflare_secret.metadata.0.name
                key  = "token"
              }
            }
          }

          args = ["tunnel", "--no-autoupdate", "run", "--token", "$(CLOUDFLARE_TOKEN)"]
        }
      }
    }
  }
}
