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

  container_repository = "${var.container_repository}/${var.project}"

  hadoop = {
    user    = "hadoop"
    version = "3.3.5"
    image_name = "${local.container_repository}/hadoop"
  }

  spark = {
    version = "3.4.0"
    image_name = "${local.container_repository}/spark"
    python_libraries = [
      "regex",
      "numpy",
      "scipy",
      "pandas",
    ]
  }

  jupyter = {
    version = "4.0.0"
    image_name = "${local.container_repository}/jupyter"
    python_libraries = [
      "matplotlib",
      "seaborn",
      "findspark",
      "pymongo",
    ]
    almond = {
      version = "0.13.13"
      scala_version = "2.13.10"
    }
  }

  hive_metastore = {
    version = "3.0.0"
    image_name = "${local.container_repository}/hive-metastore"
  }

  hue = {
    version = "4.11.0"
    image_name =  "${local.container_repository}/hue"
  }

  additional_jars = {
    gcs_connector         = "https://repo1.maven.org/maven2/com/google/cloud/bigdataoss/gcs-connector/hadoop3-2.2.12/gcs-connector-hadoop3-2.2.12-shaded.jar",
    mongo_spark_connector = "https://repo1.maven.org/maven2/org/mongodb/spark/mongo-spark-connector_2.12/10.1.1/mongo-spark-connector_2.12-10.1.1-all.jar",
  }
}
