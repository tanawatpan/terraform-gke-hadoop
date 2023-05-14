terraform {
  required_providers {
    local = {
      source = "hashicorp/local"
    }
    tls = {
      source = "hashicorp/tls"
    }
  }
}

provider "tls" {}

provider "local" {}

locals {

  hadoop = {
    user    = "hadoop"
    version = "3.3.5"
    image = {
      name = "${var.container_repository}/${var.project}/hadoop"
      tag  = "1.0"
    }
  }

  spark = {
    version = "3.4.0"
    image = {
      name = "${var.container_repository}/${var.project}/spark"
      tag  = "1.0"
    }
    python_libraries = [
      "regex",
      "numpy",
      "scipy",
      "pandas",
    ]
  }

  jupyter = {
    image = {
      name = "${var.container_repository}/${var.project}/jupyter"
      tag  = "1.0"
    }
    python_libraries = [
      "matplotlib",
      "seaborn",
      "findspark",
      "pymongo",
    ]
  }

  hive_metastore = {
    version = "3.0.0"
    image = {
      name = "${var.container_repository}/${var.project}/hive-metastore"
      tag  = "1.0"
    }
  }

  hue = {
    image = {
      name = "${var.container_repository}/${var.project}/hue"
      tag  = "4.11.0"
    }
  }

  additional_jars = {
    gcs_connector         = "https://repo1.maven.org/maven2/com/google/cloud/bigdataoss/gcs-connector/hadoop3-2.2.12/gcs-connector-hadoop3-2.2.12-shaded.jar",
    mongo_spark_connector = "https://repo1.maven.org/maven2/org/mongodb/spark/mongo-spark-connector_2.12/10.1.1/mongo-spark-connector_2.12-10.1.1-all.jar",
  }
}
