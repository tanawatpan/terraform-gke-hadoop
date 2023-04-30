resource "local_file" "hadoop_setup" {
  filename = "hadoop/setup.sh"
  content  = <<-EOT
		#!/bin/bash

		set -e
		set -x

		HADOOP_FILE="$(find /tmp/ -type f -name 'hadoop-*' | head -n 1 | xargs basename)"
		SPARK_FILE="$(find /tmp/ -type f -name 'spark-*' | head -n 1 | xargs basename)"

		function create_user {
			adduser --disabled-password --gecos 'user for Hadoop and Spark' $HADOOP_USER
			adduser $HADOOP_USER root

			su - $HADOOP_USER -c "mkdir -p /home/$HADOOP_USER/.ssh"
			mv -f /tmp/id_rsa /home/$HADOOP_USER/.ssh/id_rsa
			mv -f /tmp/id_rsa.pub /home/$HADOOP_USER/.ssh/id_rsa.pub
			chown $HADOOP_USER:$HADOOP_USER /home/$HADOOP_USER/.ssh/id_rsa /home/$HADOOP_USER/.ssh/id_rsa.pub
			chmod 600 /home/$HADOOP_USER/.ssh/id_rsa
			chmod 644 /home/$HADOOP_USER/.ssh/id_rsa.pub

			su - $HADOOP_USER -c "cat ~/.ssh/id_rsa.pub >> ~/.ssh/authorized_keys"

			rm -f /tmp/id_rsa /tmp/id_rsa.pub

			su - $HADOOP_USER -c "echo 'Host *' > ~/.ssh/config"
			su - $HADOOP_USER -c "echo '    StrictHostKeyChecking no' >> ~/.ssh/config"
			su - $HADOOP_USER -c "echo '    UserKnownHostsFile=/dev/null' >> ~/.ssh/config"
			su - $HADOOP_USER -c "echo '    LogLevel=quiet' >> ~/.ssh/config"
			su - $HADOOP_USER -c "chmod 0600 ~/.ssh/config"					
		}

		function install_hadoop {
			echo "Extracting Hadoop to /opt/hadoop ..."
			tar -xzf /tmp/$HADOOP_FILE -C /tmp
			mv -f /tmp/$(find /tmp/ -type d -name 'hadoop-*' | head -n 1 | xargs basename) $HADOOP_HOME
			rm -f /tmp/$HADOOP_FILE

			mkdir -p /data
			chown -R $HADOOP_USER:$HADOOP_USER /data
			chmod -R 700 /data

			mkdir -p $HADOOP_HOME/logs
			chown -R $HADOOP_USER:$HADOOP_USER $HADOOP_HOME
			chmod -R 755 $HADOOP_HOME
		}

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

		create_user

		install_hadoop &

		install_spark &

		wait # Wait for all background jobs to finish

		create_python_virtual_environment

		install_spark_libs

		echo "Finished installing Hadoop and Spark"
	EOT
}

resource "local_file" "entrypoint" {
  filename = "hadoop/entrypoint.sh"
  content  = <<-EOT
		#!/bin/bash

		set -e
		set -x

		NODE_TYPE=$${NODE_TYPE^^}
		echo "NODE_TYPE: $NODE_TYPE"

		function create_property() {
			cat <<-EOL
			    <property>
			        <name>$1</name>
			        <value>$2</value>
			    </property>
			EOL
		}

		function config_hadoop {
			echo "$SECONDARY_NAMENODE_HOSTNAME" >> $HADOOP_HOME/etc/hadoop/masters

			# Hadoop configuration
			cat >> $HADOOP_HOME/etc/hadoop/hadoop-env.sh <<-EOL
				export HADOOP_OPTS='-Djava.library.path=$HADOOP_HOME/lib/native'
				export HADOOP_COMMON_LIB_NATIVE_DIR="$HADOOP_HOME/lib/native"

				export JAVA_HOME=$JAVA_HOME
			EOL

			# Update core-site.xml
			cat > $HADOOP_HOME/etc/hadoop/core-site.xml <<-EOL
				<configuration>
					$(create_property fs.defaultFS					hdfs://$NAMENODE_HOSTNAME:9000 )
					$(create_property fs.AbstractFileSystem.gs.impl com.google.cloud.hadoop.fs.gcs.GoogleHadoopFS )
					$(create_property hadoop.proxyuser.hue.hosts	"*" )
					$(create_property hadoop.proxyuser.hue.groups	"*" )
					$(create_property hadoop.proxyuser.trino.hosts	"*" )
					$(create_property hadoop.proxyuser.trino.groups	"*" )
				</configuration>
			EOL

			# Update hdfs-site.xml
			cat > $HADOOP_HOME/etc/hadoop/hdfs-site.xml <<-EOL
				<configuration>
					$(create_property dfs.replication 										2 )
					$(create_property dfs.namenode.name.dir 								file:///data )
					$(create_property dfs.datanode.data.dir 								file:///data )
					$(create_property dfs.namenode.datanode.registration.ip-hostname-check	false )
					$(create_property dfs.webhdfs.enabled 									true )
				</configuration>
			EOL
		}

		function config_spark {
			# Configure spark-env.sh
			cp $SPARK_HOME/conf/spark-env.sh.template $SPARK_HOME/conf/spark-env.sh
			cat >> $SPARK_HOME/conf/spark-env.sh <<-EOL
				export HADOOP_CONF_DIR=$HADOOP_HOME/etc/hadoop
				export SPARK_MASTER_HOST=$SPARK_MASTER_HOSTNAME
				export SPARK_MASTER_PORT=7077
				export SPARK_MASTER_WEBUI_PORT=8080
				export SPARK_WORKER_CORES=$${SPARK_WORKER_CORES:=1}

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
				spark.hadoop.fs.AbstractFileSystem.gs.impl  com.google.cloud.hadoop.fs.gcs.GoogleHadoopFS

				spark.sql.catalogImplementation  hive
				spark.hadoop.hive.metastore.uris thrift://$${HIVE_METASTORE_HOSTNAME}:9083

				spark.dynamicAllocation.enabled             true
				spark.dynamicAllocation.initialExecutors    $${SPARK_INITIAL_EXECUTORS:=1}
				spark.dynamicAllocation.maxExecutors        $${SPARK_MAX_EXECUTORS:=2}
				spark.dynamicAllocation.executorIdleTimeout $${SPARK_EXECUTOR_IDLE_TIMEOUT:=60s}
			EOL
		}

		function start {
			if [ "$NODE_TYPE" == "NAMENODE" ]; then
			    [ ! -f /data/current/VERSION ] && hdfs namenode -format
			    hdfs namenode

			elif [ "$NODE_TYPE" == "DATANODE" ]; then
			    hdfs datanode

			elif [ "$NODE_TYPE" == "SPARK_MASTER" ]; then
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

			elif [ "$NODE_TYPE" == "JUPYTER" ]; then
			    echo "spark.driver.host $(hostname -i)" >> $SPARK_HOME/conf/spark-defaults.conf
			    $PYTHON_VENV_PATH/bin/jupyter lab --no-browser --config=/home/$HADOOP_USER/.jupyter/jupyter_notebook_config.py --notebook-dir=/home/$HADOOP_USER/jupyter

			else
			    echo "Error: NODE_TYPE must be set to 'NAMENODE', 'DATANODE', 'SPARK_MASTER', 'SPARK_THRIFT', 'SPARK_WORKER', 'SPARK_HISTORY' or 'JUPYTER'"
			    exit 1

			fi
		}

		config_hadoop
		config_spark
		start
	EOT
}

resource "local_file" "hadoop_dockerfile" {
  filename = "hadoop/Dockerfile"
  content  = <<-EOT
		FROM ubuntu:kinetic as ${basename(local.hadoop.image.name)}-${local.hadoop.image.tag}

		RUN apt-get -q -y update && \
			apt-get -q -y install wget ssh net-tools telnet curl dnsutils jq openjdk-11-jre python3 python3-venv

		RUN wget -q -P /tmp https://downloads.apache.org/hadoop/common/hadoop-${local.hadoop.version}/hadoop-${local.hadoop.version}.tar.gz && \
			wget -q -P /tmp https://downloads.apache.org/spark/spark-${local.spark.version}/spark-${local.spark.version}-bin-hadoop3.tgz

		COPY ${basename(local_file.public_key.filename)} /tmp/${basename(local_file.public_key.filename)}
		COPY ${basename(local_file.private_key.filename)}  /tmp/${basename(local_file.private_key.filename)}

		ENV JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64

		ENV HADOOP_USER="${local.hadoop.user}"
		ENV HADOOP_HOME=/opt/hadoop
		ENV HADOOP_HDFS_HOME=$HADOOP_HOME
		ENV HADOOP_MAPRED_HOME=$HADOOP_HOME
		ENV HADOOP_COMMON_HOME=$HADOOP_HOME
		ENV HADOOP_CONF_DIR=$HADOOP_HOME/etc/hadoop
		ENV HADOOP_OPTS='-Djava.library.path=$HADOOP_HOME/lib/native'
		ENV HADOOP_COMMON_LIB_NATIVE_DIR="$HADOOP_HOME/lib/native"

		ENV SPARK_HOME=/opt/spark
		ENV PYTHON_VENV="python3"
		ENV PYTHON_VENV_PATH="/home/$HADOOP_USER/$PYTHON_VENV"

		ENV PATH=$HADOOP_HOME/bin:$HADOOP_HOME/sbin:$SPARK_HOME/bin:$SPARK_HOME/sbin:$PATH

		ENV EXTERNAL_JARS="${join(" ", [for lib, url in local.external_jars : url])}"

		COPY ${basename(local_file.hadoop_setup.filename)} /tmp/${basename(local_file.hadoop_setup.filename)}
		RUN chmod +x /tmp/${basename(local_file.hadoop_setup.filename)}
		RUN /tmp/${basename(local_file.hadoop_setup.filename)}


		USER $HADOOP_USER
		WORKDIR /home/$HADOOP_USER
		COPY --chown=$HADOOP_USER:$HADOOP_USER ${basename(local_file.entrypoint.filename)} ${basename(local_file.entrypoint.filename)}
		CMD ["/bin/bash", "${basename(local_file.entrypoint.filename)}"]
 	 EOT

  provisioner "local-exec" {
    # gcloud builds submit --tag ${local.hadoop.image.name}:${local.hadoop.image.tag} hadoop/ 
    command = <<-EOT
		set -x
		set -e
		docker build --platform linux/amd64 -t ${basename(local.hadoop.image.name)}:${local.hadoop.image.tag} ${dirname(self.filename)}
		docker tag ${basename(local.hadoop.image.name)}:${local.hadoop.image.tag} ${local.hadoop.image.name}:${local.hadoop.image.tag}
		docker push ${local.hadoop.image.name}:${local.hadoop.image.tag}
	EOT
  }

  lifecycle {
    replace_triggered_by = [
      local_file.private_key.id,
      local_file.public_key.id,
      local_file.entrypoint.id,
      local_file.hadoop_setup.id,
    ]
  }
}
