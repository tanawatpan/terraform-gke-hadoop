resource "local_file" "install_spark" {
  filename = "spark/install-spark.sh"
  content  = <<-EOT
		#!/bin/bash

		set -e
		set -x

		SPARK_FILE="$(find /tmp/ -type f -name 'spark-*' | head -n 1 | xargs basename)"

		function install_spark {
			echo "Extracting and moving Spark to $SPARK_HOME ..."
			tar -xzf /tmp/$SPARK_FILE -C /tmp
			mv -f /tmp/$(find /tmp/ -type d -name 'spark-*' | head -n 1 | xargs basename) $SPARK_HOME
			rm -f /tmp/$SPARK_FILE

			chown -R $HADOOP_USER:$HADOOP_USER $SPARK_HOME
			chmod -R 755 $SPARK_HOME
		}

		function create_python_virtual_environment {
			su - $HADOOP_USER -c "python3 -m venv $PYTHON_VENV"
			su - $HADOOP_USER -c " echo \"source $PYTHON_VENV_PATH/bin/activate\" >> ~/.bashrc "
			su - $HADOOP_USER -c "
				set -x
				source $PYTHON_VENV_PATH/bin/activate
				pip3 install -q ${join(" ", local.spark.python_libraries)}
			"
		}

		function install_spark_libs {
			echo "Installing Spark libraries ..."
			for URL in $EXTERNAL_JARS; do
				echo $URL
				su - $HADOOP_USER -c "wget -q -P /tmp $URL "
				su - $HADOOP_USER -c "cp   -f /tmp/$(basename $URL) $SPARK_HOME/jars "
				su - $HADOOP_USER -c "mv   -f /tmp/$(basename $URL) $HADOOP_HOME/share/hadoop/common/lib "
			done
		}

		function create_spark_configuration_script {
			cat >> /home/$HADOOP_USER/config.sh <<-'EOF'

				function config_spark {
					# Configure spark-env.sh
					cp $SPARK_HOME/conf/spark-env.sh.template $SPARK_HOME/conf/spark-env.sh
					cat >> $SPARK_HOME/conf/spark-env.sh <<-EOL
						export HADOOP_CONF_DIR=$HADOOP_HOME/etc/hadoop
						export SPARK_MASTER_HOST=$SPARK_MASTER_HOSTNAME
						export SPARK_MASTER_PORT=7077
						export SPARK_MASTER_WEBUI_PORT=8080
						export SPARK_WORKER_CORES=$${SPARK_WORKER_CORES:=1}
						export SPARK_WORKER_MEMORY=$${SPARK_WORKER_MEMORY:=2g}

						export LD_LIBRARY_PATH=$HADOOP_HOME/lib/native:\\\$LD_LIBRARY_PATH
					EOL

					# Configure spark-defaults
					cat > $SPARK_HOME/conf/spark-defaults.conf <<-EOL
						spark.master             spark://$SPARK_MASTER_HOSTNAME:7077
						spark.driver.cores       $${SPARK_DRIVER_CORES:=1}
						spark.driver.memory      $${SPARK_DRIVER_MEMORY:=512m}
						spark.cores.max          $${SPARK_CORE_MAX:=4}
						spark.executor.cores     $${SPARK_EXECUTOR_CORES:=1}
						spark.executor.memory    $${SPARK_EXECUTOR_MEMORY:=2g}
						spark.executor.instances $${SPARK_EXECUTOR_INSTANCES:=1}
						spark.serializer         org.apache.spark.serializer.KryoSerializer

						spark.eventLog.enabled          true
						spark.eventLog.dir              $${SPARK_LOG_DIR:=hdfs:/spark-events}
						spark.eventLog.compress         false
						spark.history.fs.logDirectory   $${SPARK_LOG_DIR:=hdfs:/spark-events}

						spark.hadoop.fs.defaultFS                   hdfs://$NAMENODE_HOSTNAME:9000
						spark.sql.warehouse.dir                     hdfs://$${NAMENODE_HOSTNAME}:9000/$${HIVE_WAREHOUSE:=/user/hive/warehouse}
						spark.hadoop.fs.hdfs.impl                   org.apache.hadoop.hdfs.DistributedFileSystem
						spark.hadoop.fs.gs.impl						com.google.cloud.hadoop.fs.gcs.GoogleHadoopFileSystem
						spark.hadoop.fs.AbstractFileSystem.gs.impl  com.google.cloud.hadoop.fs.gcs.GoogleHadoopFS

						spark.sql.catalogImplementation  hive
						spark.hadoop.hive.metastore.uris thrift://$${HIVE_METASTORE_HOSTNAME}:9083

						spark.dynamicAllocation.enabled             true
						spark.dynamicAllocation.initialExecutors    $${SPARK_INITIAL_EXECUTORS:=1}
						spark.dynamicAllocation.maxExecutors        $${SPARK_MAX_EXECUTORS:=2}
						spark.dynamicAllocation.executorIdleTimeout $${SPARK_EXECUTOR_IDLE_TIMEOUT:=60s}
					EOL
				}

			EOF
		}

		install_spark

		create_python_virtual_environment

		install_spark_libs

		create_spark_configuration_script

		echo "Finished installing Spark"
	EOT
}

resource "local_file" "spark_entrypoint" {
  filename = "spark/spark-entrypoint.sh"
  content  = <<-EOT
		#!/bin/bash

		set -e
		set -x

		source /home/$HADOOP_USER/config.sh

		AVAILABLE_CORES=$(nproc)
		AVAILABLE_MEMORY=$(free -g | awk '/^Mem:/ {print $2}')

		SPARK_WORKER_CORES=$(( AVAILABLE_CORES > 1 ? AVAILABLE_CORES - 1 : 1 ))
		SPARK_WORKER_MEMORY="$(( AVAILABLE_MEMORY > 3 ? AVAILABLE_MEMORY - 2 : 1 ))g"

		NODE_TYPE=$${NODE_TYPE^^}
		echo "NODE_TYPE: $NODE_TYPE"

		function start {
			if [ "$NODE_TYPE" == "SPARK_MASTER" ]; then
			    SPARK_NO_DAEMONIZE=true $SPARK_HOME/sbin/start-master.sh

			elif [ "$NODE_TYPE" == "SPARK_THRIFT" ]; then
			    echo "spark.driver.host $(hostname -i)" >> $SPARK_HOME/conf/spark-defaults.conf
			    SPARK_NO_DAEMONIZE=true $SPARK_HOME/sbin/start-thriftserver.sh \
			        --hiveconf hive.server2.thrift.bind.host=0.0.0.0 \
			        --hiveconf hive.server2.thrift.port=10000 \
			        --master spark://$SPARK_MASTER_HOSTNAME:7077

			elif [ "$NODE_TYPE" == "SPARK_WORKER" ]; then
			    SPARK_NO_DAEMONIZE=true $SPARK_HOME/sbin/start-worker.sh spark://$SPARK_MASTER_HOSTNAME:7077

			elif [ "$NODE_TYPE" == "SPARK_HISTORY" ]; then
			    hdfs dfs -ls / || sleep 15 && hdfs dfs -mkdir -p /spark-events
			    SPARK_NO_DAEMONIZE=true $SPARK_HOME/sbin/start-history-server.sh

			else
			    echo "Error: NODE_TYPE must be set to 'SPARK_MASTER', 'SPARK_THRIFT', 'SPARK_WORKER', 'SPARK_HISTORY' "
			    exit 1

			fi
		}

		config_hadoop
		config_spark
		start
	EOT
}

resource "local_file" "spark_dockerfile" {
  depends_on = [local_file.hadoop_dockerfile]
  filename   = "spark/Dockerfile"
  content    = <<-EOT
		FROM ${local.hadoop.image_name}:${local.hadoop.version}

		RUN echo "${basename(local.spark.image_name)}:${local.spark.version}" > /tmp/image_name

		ARG EXTERNAL_JARS="${join(" ", [for lib, url in local.additional_jars : url])}"

		USER root

		RUN wget -q -P /tmp https://downloads.apache.org/spark/spark-${local.spark.version}/spark-${local.spark.version}-bin-hadoop3.tgz

		ENV SPARK_HOME=/opt/spark
		ENV PYTHON_VENV="python3"
		ENV PYTHON_VENV_PATH="/home/$HADOOP_USER/$PYTHON_VENV"
		ENV PATH=$SPARK_HOME/bin:$SPARK_HOME/sbin:$PATH

		COPY ${basename(local_file.install_spark.filename)} /tmp/${basename(local_file.install_spark.filename)}
		RUN chmod +x /tmp/${basename(local_file.install_spark.filename)}
		RUN /tmp/${basename(local_file.install_spark.filename)}

		USER $HADOOP_USER
		WORKDIR /home/$HADOOP_USER
		COPY --chown=$HADOOP_USER:$HADOOP_USER ${basename(local_file.spark_entrypoint.filename)} ${basename(local_file.spark_entrypoint.filename)}
		CMD ["/bin/bash", "${basename(local_file.spark_entrypoint.filename)}"]
 	 EOT

  provisioner "local-exec" {
    command = <<-EOT
		gcloud builds submit --tag ${local.spark.image_name}:${local.spark.version} ${dirname(self.filename)}
	EOT
  }

  lifecycle {
    replace_triggered_by = [
      local_file.spark_entrypoint.content,
      local_file.install_spark.content,
    ]
  }
}
