variable "project" {
  type        = string
  description = "Google Cloud project ID"

  validation {
    condition     = length(var.project) > 0
    error_message = "The project ID must not be empty."
  }
}

variable "region" {
  type        = string
  description = "Google Cloud deployment region"

  validation {
    condition     = can(regex("^([a-z]+-[a-z]+[1-9])$", var.region))
    error_message = "The region must follow Google Cloud's naming convention (e.g., 'us-central1')."
  }
}

variable "zone" {
  type        = string
  description = "Google Cloud deployment zone"

  validation {
    condition     = can(regex("^([a-z]+-[a-z]+[1-9]-[a-z])$", var.zone))
    error_message = "The zone must follow Google Cloud's naming convention (e.g., 'us-central1-a')."
  }
}

variable "cluster_name" {
  type        = string
  description = "Name of the GKE cluster"
}

variable "node_count" {
  type        = string
  description = "Number of nodes in the GKE cluster"
}

variable "machine_type" {
  type        = string
  description = "Machine type for the GKE cluster"
}

variable "disk_size_gb" {
  type        = string
  description = "Disk size for the GKE cluster"
}
