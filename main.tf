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


variable "web_domain" {
  type        = string
  description = "Web UI domain name, Please make sure to update your NS records to point to Google Cloud DNS"

  validation {
    condition     = can(regex("^([a-zA-Z0-9-_]+\\.)+[a-zA-Z]{2,}$", var.web_domain))
    error_message = "The domain name must be a valid domain (e.g., 'example.com')."
  }
}

provider "google" {
  project = var.project
  region  = var.region
  zone    = var.zone
}

locals {
  image = {
    name = "gcr.io/${var.project}/hadoo-spark"
    tag  = "0.1"
  }
  hadoop_version = "3.3.5"
  spark_version  = "3.4.0"
}
