variable "project" {
  type = string
}

variable "region" {
  type = string
}

variable "zone" {
  type = string
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
