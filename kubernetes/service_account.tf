# Service Account
resource "google_service_account" "storage_admin" {
  account_id   = "storage-admin"
  display_name = "Storage Admin"
}

resource "google_project_iam_member" "storage_admin" {
  project = var.project
  role    = "roles/storage.admin"
  member  = "serviceAccount:${google_service_account.storage_admin.email}"
}

resource "google_service_account_iam_binding" "iam_binding" {
  service_account_id = google_service_account.storage_admin.name
  role               = "roles/iam.workloadIdentityUser"
  members = [
    "serviceAccount:${var.project}.svc.id.goog[${kubernetes_service_account.storage_admin.metadata.0.namespace}/${kubernetes_service_account.storage_admin.metadata.0.name}]",
  ]
}

resource "kubernetes_service_account" "storage_admin" {
  metadata {
    name      = "storage-admin"
    namespace = kubernetes_namespace.hadoop.metadata.0.name
    annotations = {
      "iam.gke.io/gcp-service-account" = google_service_account.storage_admin.email
    }
  }
}
