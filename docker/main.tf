terraform {
  required_providers {
    local = {
      source = "hashicorp/local"
    }
    tls = {
      source = "hashicorp/tls"
    }
    google = {
      source = "hashicorp/google"
    }
  }
}

provider "tls" {}

provider "local" {}

provider "google" {
  project = var.project
  region  = var.region
  zone    = var.zone
}

resource "google_artifact_registry_repository" "repository" {
  location      = var.region
  repository_id = var.artifact_repository
  format        = "DOCKER"
}

locals {
  container_repository = "${var.region}-docker.pkg.dev/${var.project}/${var.artifact_repository}"

  hadoop = {
    user       = "hadoop"
    version    = "3.3.5"
    image_name = "${local.container_repository}/hadoop"
  }

  spark = {
    version    = "3.4.0"
    image_name = "${local.container_repository}/spark"
    python_libraries = [
      "regex",
      "numpy",
      "scipy",
      "pandas"
    ]
  }

  jupyter = {
    version    = "4.0.0"
    image_name = "${local.container_repository}/jupyter"
    python = {
      version = "3.11"
      libraries = [
        "matplotlib",
        "seaborn",
        "findspark",
        "pymongo",
        "tensorflow==2.12.*"
      ]
    }
    almond = {
      version       = "0.13.13"
      scala_version = "2.13.10"
    }
  }

  hive_metastore = {
    version    = "3.0.0"
    image_name = "${local.container_repository}/hive-metastore"
  }

  hue = {
    version    = "4.11.0"
    image_name = "${local.container_repository}/hue"
  }

  additional_jars = {
    gcs_connector         = "https://repo1.maven.org/maven2/com/google/cloud/bigdataoss/gcs-connector/hadoop3-2.2.12/gcs-connector-hadoop3-2.2.12-shaded.jar",
    mongo_spark_connector = "https://repo1.maven.org/maven2/org/mongodb/spark/mongo-spark-connector_2.12/10.1.1/mongo-spark-connector_2.12-10.1.1-all.jar",
  }
}
