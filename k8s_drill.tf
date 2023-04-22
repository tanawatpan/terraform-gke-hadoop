resource "kubernetes_namespace" "drill" {
  metadata {
    name = "drill"
  }
}

resource "kubernetes_service" "drill_service" {
  metadata {
    name      = "drill-service"
    namespace = kubernetes_namespace.drill.metadata.0.name
  }

  spec {
    selector = {
      app = "drill"
    }

    port {
      name        = "web"
      port        = 8047
      target_port = 8047
      protocol    = "TCP"
    }

    port {
      name        = "jdbc"
      port        = 31010
      target_port = 31010
      protocol    = "TCP"
    }

    type = "ClusterIP"
  }

  lifecycle {
    ignore_changes = [
      metadata.0.annotations,
    ]
  }
}

resource "kubernetes_deployment" "drill" {
  metadata {
    name      = "drill"
    namespace = kubernetes_namespace.drill.metadata.0.name
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "drill"
      }
    }

    template {
      metadata {
        labels = {
          app = "drill"
        }
      }

      spec {
        container {
          name  = "drill"
          image = "${local.drill.image.name}:${local.drill.image.tag}"

          security_context {
            run_as_user = 0
          }

          command = ["/bin/bash", "-c"]
          args = [<<EOT
				set -e
				set -x
				cat > $DRILL_HOME/conf/storage-plugins-override.conf <<-EOL
					"storage": {
					  dfs: {
					    type : "file",
					    connection : "hdfs://${kubernetes_service_v1.namenode.metadata.0.name}.${kubernetes_namespace.hadoop.metadata.0.name}.svc.cluster.local:${kubernetes_service_v1.namenode.spec.0.port.0.target_port}",
					    workspaces : {
					      "tmp" : {
					        "location" : "/tmp",
					        "writable" : true,
					        "defaultInputFormat" : null,
					        "allowAccessOutsideWorkspace" : false
					      },
					      "root" : {
					        "location" : "/",
					        "writable" : false,
					        "defaultInputFormat" : null,
					        "allowAccessOutsideWorkspace" : false
					      }
					    },
					    formats : {
					      "parquet" : {
					        "type" : "parquet"
					      },
					      "json" : {
					        "type" : "json",
					        "extensions" : [ "json" ]
					      },
					      "sequencefile" : {
					        "type" : "sequencefile",
					        "extensions" : [ "seq" ]
					      },
					      "csvh" : {
					        "type" : "text",
					        "extensions" : [ "csvh" ],
					        "extractHeader" : true
					      },
					      "psv" : {
					        "type" : "text",
					        "extensions" : [ "tbl" ],
					        "fieldDelimiter" : "|"
					      },
					      "avro" : {
					        "type" : "avro",
					        "extensions" : [ "avro" ]
					      },
					      "tsv" : {
					        "type" : "text",
					        "extensions" : [ "tsv" ],
					        "fieldDelimiter" : "\t"
					      },
					      "csv" : {
					        "type" : "text",
					        "extensions" : [ "csv" ],
					        "extractHeader" : true
					      },
					      "xml" : {
					        "type" : "xml",
					        "extensions" : [ "xml" ],
					        "dataLevel" : 1
					      },
					      "pdf" : {
					        "type" : "pdf",
					        "extensions" : [ "pdf" ],
					        "extractHeaders" : true,
					        "extractionAlgorithm" : "basic"
					      },
					      "hdf5" : {
					        "type" : "hdf5",
					        "extensions" : [ "h5" ],
					        "defaultPath" : null
					      },
					      "httpd" : {
					        "type" : "httpd",
					        "extensions" : [ "httpd" ],
					        "logFormat" : "common\ncombined"
					      },
					      "excel" : {
					        "type" : "excel",
					        "extensions" : [ "xlsx" ],
					        "lastRow" : 1048576
					      }
					    },
					    enabled: true
					  }
					}
					"storage": {
					  gcs: {
					    type : "file",
					    connection : "gs://bucket",
					    workspaces : {
					    "tmp" : {
					      "location" : "/tmp",
					      "writable" : true,
					      "defaultInputFormat" : null,
					      "allowAccessOutsideWorkspace" : false
					    },
					    "root" : {
					      "location" : "/",
					      "writable" : false,
					      "defaultInputFormat" : null,
					      "allowAccessOutsideWorkspace" : false
					    }
					    },
					    formats : {
					    "parquet" : {
					      "type" : "parquet"
					    },
					    "json" : {
					      "type" : "json",
					      "extensions" : [ "json" ]
					    },
					    "sequencefile" : {
					      "type" : "sequencefile",
					      "extensions" : [ "seq" ]
					    },
					    "csvh" : {
					      "type" : "text",
					      "extensions" : [ "csvh" ],
					      "extractHeader" : true
					    },
					    "psv" : {
					      "type" : "text",
					      "extensions" : [ "tbl" ],
					      "fieldDelimiter" : "|"
					    },
					    "avro" : {
					      "type" : "avro",
					      "extensions" : [ "avro" ]
					    },
					    "tsv" : {
					      "type" : "text",
					      "extensions" : [ "tsv" ],
					      "fieldDelimiter" : "\t"
					    },
					    "csv" : {
					      "type" : "text",
					      "extensions" : [ "csv" ],
					      "extractHeader" : true
					    },
					    "xml" : {
					      "type" : "xml",
					      "extensions" : [ "xml" ],
					      "dataLevel" : 1
					    },
					    "pdf" : {
					      "type" : "pdf",
					      "extensions" : [ "pdf" ],
					      "extractHeaders" : true,
					      "extractionAlgorithm" : "basic"
					    },
					    "hdf5" : {
					      "type" : "hdf5",
					      "extensions" : [ "h5" ],
					      "defaultPath" : null
					    },
					    "httpd" : {
					      "type" : "httpd",
					      "extensions" : [ "httpd" ],
					      "logFormat" : "common\ncombined"
					    },
					    "excel" : {
					      "type" : "excel",
					      "extensions" : [ "xlsx" ],
					      "lastRow" : 1048576
					    }
					    },
					    enabled: true
					  }
					}
				EOL
				cat > $DRILL_HOME/conf/core-site.xml <<-EOL
					<configuration>
					  <property>
					    <name>fs.gs.impl</name>
					    <value>com.google.cloud.hadoop.fs.gcs.GoogleHadoopFileSystem</value>
					  </property>
					  <property>
					    <name>fs.AbstractFileSystem.gs.impl</name>
					    <value>com.google.cloud.hadoop.fs.gcs.GoogleHadoopFS</value>
					  </property>
					</configuration>
				EOL
				rm -f $DRILL_HOME/jars/3rdparty/mongodb-driver-*.jar
				wget -P $DRILL_HOME/jars/3rdparty https://repo1.maven.org/maven2/org/mongodb/mongodb-driver-sync/${local.drill.mongodb_driver_version}/mongodb-driver-sync-${local.drill.mongodb_driver_version}.jar
				wget -P $DRILL_HOME/jars/3rdparty https://repo1.maven.org/maven2/org/mongodb/mongodb-driver-core/${local.drill.mongodb_driver_version}/mongodb-driver-core-${local.drill.mongodb_driver_version}.jar
				wget -P $DRILL_HOME/jars/3rdparty ${local.external_jars.gcs_connector} 
				$DRILL_HOME/bin/drill-embedded
			EOT
          ]

          port {
            name           = "web"
            container_port = 8047
          }

          port {
            name           = "jdbc"
            container_port = 31010
          }

          stdin = true
          tty   = true
        }
      }
    }
  }
}
