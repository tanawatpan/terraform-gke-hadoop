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

variable "artifact_repository" {
  type        = string
  description = "Artifact Registry repository name"
}
