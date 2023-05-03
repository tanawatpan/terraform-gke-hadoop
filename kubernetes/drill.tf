resource "kubernetes_namespace" "drill" {
  metadata {
    name = "drill"
  }
}

resource "kubernetes_service_v1" "drill_service" {
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

resource "kubernetes_service" "drills" {
  metadata {
    name      = "drills"
    namespace = kubernetes_namespace.drill.metadata.0.name
  }

  spec {
    selector = {
      app = "drill"
    }
    cluster_ip = "None"
  }

  lifecycle {
    ignore_changes = [
      metadata.0.annotations,
    ]
  }
}

resource "kubernetes_stateful_set" "drill" {
  metadata {
    name      = local.drill.name
    namespace = kubernetes_namespace.drill.metadata.0.name
  }

  spec {
    service_name = "drills"
    replicas     = local.drill.replicas

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
          name  = local.drill.name
          image = "${local.drill.image.name}:${local.drill.image.tag}"

          security_context {
            run_as_user = 0
          }

          env {
            name  = "ZOO_KEEPER_URL"
            value = local.drill.zookeeper.package_url
          }
          env {
            name  = "ZOO_DATA_DIR"
            value = local.drill.zookeeper.data_directory
          }
          env {
            name  = "ZOO_HOME"
            value = local.drill.zookeeper.home
          }
          env {
            name  = "REPLICAS"
            value = local.drill.replicas
          }

          command = ["/bin/bash", "-c"]
          args = [<<-EOT
				set -e
				set -x

				wget -P /tmp $ZOO_KEEPER_URL
				tar -xzf /tmp/$(basename $ZOO_KEEPER_URL) -C /tmp 
				mv -f /tmp/$(basename $ZOO_KEEPER_URL .tar.gz) $ZOO_HOME

				cp $ZOO_HOME/conf/zoo_sample.cfg $ZOO_HOME/conf/zoo.cfg
				sed -i "s|^dataDir=.*$|dataDir=$${ZOO_DATA_DIR}|" $ZOO_HOME/conf/zoo.cfg 
				sed -i "s|^clientPort=.*$|clientPort=${local.drill.zookeeper.port}|" $ZOO_HOME/conf/zoo.cfg 
				echo "clientPortAddress=0.0.0.0" >> $ZOO_HOME/conf/zoo.cfg

				for ((i=0;i<$REPLICAS;i++)); do
				    echo "server.$i=${local.drill.name}-$i.${kubernetes_service.drills.metadata.0.name}.${kubernetes_namespace.drill.metadata.0.name}.svc.cluster.local:2888:3888" >> $ZOO_HOME/conf/zoo.cfg
				    NODES+="${local.drill.name}-$i.${kubernetes_service.drills.metadata.0.name}.${kubernetes_namespace.drill.metadata.0.name}.svc.cluster.local:${local.drill.zookeeper.port},"
				done

				POD_NAME=$(hostname)
				mkdir -p $${ZOO_DATA_DIR}
				echo $${POD_NAME##*-} > $${ZOO_DATA_DIR}/myid

				$ZOO_HOME/bin/zkServer.sh start

				NODES=$${NODES:0:-1}
				sed -i "s/\(zk.connect:\).*/\1 \"$NODES\"/" $$DRILL_HOME/conf/drill-override.conf

				cat > $DRILL_HOME/conf/storage-plugins-override.conf <<-EOL
					"storage": {
					  dfs: {
					    type : "file",
					    connection : "hdfs://namenode-0.${kubernetes_service_v1.namenode.metadata.0.name}.${kubernetes_namespace.hadoop.metadata.0.name}.svc.cluster.local:9000",
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
					    connection : "gs://<your_bucket_name>",
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
					    enabled: false
					  }
					}
					"storage": {
					  hive: {
					    type: "hive",
					    configProps: {
					      "hive.metastore.uris": "thrift://${kubernetes_service_v1.hive_metastore.metadata.0.name}.${kubernetes_namespace.hive_metastore.metadata.0.name}.svc.cluster.local:${kubernetes_service_v1.hive_metastore.spec.0.port.0.target_port}",
					      "hive.metastore.sasl.enabled": "false",
					      "fs.default.name": "hdfs://namenode-0.${kubernetes_service_v1.namenode.metadata.0.name}.${kubernetes_namespace.hadoop.metadata.0.name}.svc.cluster.local:9000/"
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

				$DRILL_HOME/bin/drillbit.sh start && sleep 45

				if curl --max-time 15 -s localhost:${kubernetes_service_v1.drill_service.spec.0.port.0.target_port} >/dev/null; then
					echo "Apache Drill is accessible at port ${kubernetes_service_v1.drill_service.spec.0.port.0.target_port}"
				else
					echo "Error: Apache Drill is not accessible at port ${kubernetes_service_v1.drill_service.spec.0.port.0.target_port}"
					exit 1
				fi

				$DRILL_HOME/bin/sqlline
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
