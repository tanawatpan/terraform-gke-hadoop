terraform {
  required_providers {
    google = {
      source = "hashicorp/google"
    }
    kubernetes = {
      source = "hashicorp/kubernetes"
    }
    kubectl = {
      source = "gavinbunney/kubectl"
    }
    helm = {
      source = "hashicorp/helm"
    }
  }
}

provider "google" {
  project = var.project
  region  = var.region
  zone    = var.zone
}

data "google_client_config" "provider" {}

data "google_container_cluster" "cluster" {
  name     = local.cluster_name
  location = var.zone
}

provider "kubernetes" {
  host  = "https://${data.google_container_cluster.cluster.endpoint}"
  token = data.google_client_config.provider.access_token
  cluster_ca_certificate = base64decode(
    data.google_container_cluster.cluster.master_auth[0].cluster_ca_certificate,
  )
}

provider "kubectl" {
  host  = "https://${data.google_container_cluster.cluster.endpoint}"
  token = data.google_client_config.provider.access_token
  cluster_ca_certificate = base64decode(
    data.google_container_cluster.cluster.master_auth[0].cluster_ca_certificate,
  )
  load_config_file = false
}

provider "helm" {
  kubernetes {
    host  = "https://${data.google_container_cluster.cluster.endpoint}"
    token = data.google_client_config.provider.access_token
    cluster_ca_certificate = base64decode(
      data.google_container_cluster.cluster.master_auth[0].cluster_ca_certificate,
    )
  }
}

locals {
  cluster_name = "cluster-1"

  hadoop = {
    image = {
      name = "gcr.io/${var.project}/hadoop-spark"
      tag  = "1.1.0"
    }
  }

  jupyter = {
    image = {
      name = "gcr.io/${var.project}/jupyter"
      tag  = "1.0"
    }
  }

  hive_metastore = {
    image = {
      name = "gcr.io/${var.project}/hive-metastore"
      tag  = "1.0"
    }
  }

  drill = {
    name     = "drill"
    replicas = 2
    image = {
      name = "apache/drill"
      tag  = "latest-openjdk-11"
    }
    zookeeper = {
      port           = 2181
      home           = "/opt/zookeeper"
      data_directory = "/var/lib/zookeeper"
      package_url    = "https://downloads.apache.org/zookeeper/stable/apache-zookeeper-3.7.1-bin.tar.gz"
    }
    mongodb_driver_version = "4.4.2"
  }

  hue = {
    image = {
      name = "gcr.io/${var.project}/hue"
      tag  = "4.11.0"
    }
    postgres = {
      version  = "9.5"
      hostname = "postgres-hue"
      user     = "hue"
      password = "${var.hue_postgres_password}"
      database = "hue"
    }
  }

  external_jars = {
    gcs_connector         = "https://repo1.maven.org/maven2/com/google/cloud/bigdataoss/gcs-connector/hadoop3-2.2.12/gcs-connector-hadoop3-2.2.12-shaded.jar",
    mongo_spark_connector = "https://repo1.maven.org/maven2/org/mongodb/spark/mongo-spark-connector_2.12/10.1.1/mongo-spark-connector_2.12-10.1.1-all.jar",
  }
}
