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
  name     = var.cluster_name
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
  container_repository = "${var.region}-docker.pkg.dev/${var.project}/${var.artifact_repository}"

  hadoop = {
    user       = "hadoop"
    version    = "3.3.5"
    image_name = "${local.container_repository}/hadoop"
  }

  spark = {
    version    = "3.4.0"
    image_name = "${local.container_repository}/spark"
  }

  jupyter = {
    version    = "4.0.0"
    image_name = "${local.container_repository}/jupyter"
  }

  hive_metastore = {
    version    = "3.0.0"
    image_name = "${local.container_repository}/hive-metastore"

    warehouse = "user/hive/warehouse"

    mysql = {
      image = {
        name = "mariadb"
        tag  = "10.11"
      }
      root_password = var.hive_metastore_mysql_password
      user          = "admin"
      password      = var.hive_metastore_mysql_password
      database      = "metastore_db"
    }
  }

  drill = {
    name     = "drill"
    replicas = 1

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

  trino = {
    worker = {
      replicas = 2
    }
  }

  hue = {
    replicas = 1

    version    = "4.11.0"
    image_name = "${local.container_repository}/hue"

    postgres = {
      version  = "14.7"
      hostname = "postgres-hue"
      user     = "hue"
      password = "${var.hue_postgres_password}"
      database = "hue"
    }
  }

  additional_jars = {
    gcs_connector         = "https://repo1.maven.org/maven2/com/google/cloud/bigdataoss/gcs-connector/hadoop3-2.2.12/gcs-connector-hadoop3-2.2.12-shaded.jar",
    mongo_spark_connector = "https://repo1.maven.org/maven2/org/mongodb/spark/mongo-spark-connector_2.12/10.1.1/mongo-spark-connector_2.12-10.1.1-all.jar",
  }
}
