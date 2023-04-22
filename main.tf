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

locals {
  cluster_name = "hadoop"

  hadoop = {
    user    = "hadoop"
    version = "3.3.5"
    image = {
      name = "gcr.io/${var.project}/hadoop-spark"
      tag  = "1.0"
    }
  }

  spark = {
    version = "3.4.0"
  }

  jupyter = {
    image = {
      name = "gcr.io/${var.project}/jupyter"
      tag  = "1.0"
    }
    python_libraries = [
      "numpy",
      "pandas",
      "matplotlib",
      "seaborn",
      "findspark",
      "pymongo",
    ]
  }

  drill = {
    image = {
      name = "apache/drill"
      tag  = "latest-openjdk-11"
    }
    mongodb_driver_version = "4.4.2"
  }

  external_jars = {
    gcs_connector         = "https://repo1.maven.org/maven2/com/google/cloud/bigdataoss/gcs-connector/hadoop3-2.2.12/gcs-connector-hadoop3-2.2.12-shaded.jar",
    mongo_spark_connector = "https://repo1.maven.org/maven2/org/mongodb/spark/mongo-spark-connector_2.12/10.1.1/mongo-spark-connector_2.12-10.1.1-all.jar",
  }
}
