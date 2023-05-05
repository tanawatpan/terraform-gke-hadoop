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
      name = "gcr.io/${var.project}/hadoop-spark"
      tag  = "1.1.0"
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
      "scipy",
      "pandas",
      "matplotlib",
      "seaborn",
      "findspark",
      "pymongo",
    ]
  }

  hive_metastore = {
    version = "3.0.0"
    image = {
      name = "gcr.io/${var.project}/hive-metastore"
      tag  = "1.0"
    }
  }

  hue = {
    image = {
      name = "gcr.io/${var.project}/hue"
      tag  = "4.11.0"
    }
  }

  external_jars = {
    gcs_connector         = "https://repo1.maven.org/maven2/com/google/cloud/bigdataoss/gcs-connector/hadoop3-2.2.12/gcs-connector-hadoop3-2.2.12-shaded.jar",
    mongo_spark_connector = "https://repo1.maven.org/maven2/org/mongodb/spark/mongo-spark-connector_2.12/10.1.1/mongo-spark-connector_2.12-10.1.1-all.jar",
  }
}
