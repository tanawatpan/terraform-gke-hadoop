
resource "tls_private_key" "ssh" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "local_file" "private_key" {
  content         = tls_private_key.ssh.private_key_pem
  filename        = "hadoop/id_rsa"
  file_permission = "0600"

  lifecycle {
    replace_triggered_by = [
      tls_private_key.ssh.id
    ]
  }
}

resource "local_file" "public_key" {
  content         = trimspace(tls_private_key.ssh.public_key_openssh)
  filename        = "hadoop/id_rsa.pub"
  file_permission = "0644"

  lifecycle {
    replace_triggered_by = [
      tls_private_key.ssh.id,
      local_file.private_key.id
    ]
  }
}

resource "local_file" "setup" {
  filename = "hadoop/setup.sh"
  content  = <<-EOT
		#!/bin/bash

		set -e
		set -x

		JAVA_HOME="/usr/lib/jvm/java-11-openjdk-amd64"

		HADOOP_USER="hadoop"
		HADOOP_HOME="/opt/hadoop"
		HADOOP_FILE="$(find /tmp/ -type f -name 'hadoop-*' | head -n 1 | xargs basename)"

		SPARK_HOME="/opt/spark"
		SPARK_FILE="$(find /tmp/ -type f -name 'spark-*' | head -n 1 | xargs basename)"

		function create_user {
			adduser --disabled-password --gecos 'user for Hadoop, Yarn, and Spark' $HADOOP_USER
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

		function config_environment_variables {
			su - $HADOOP_USER -c "cat >> ~/.bashrc <<-EOL
				export HADOOP_HOME=$HADOOP_HOME
				export HADOOP_HDFS_HOME=$HADOOP_HOME
				export HADOOP_MAPRED_HOME=$HADOOP_HOME
				export HADOOP_COMMON_HOME=$HADOOP_HOME
				export HADOOP_CONF_DIR=$HADOOP_HOME/etc/hadoop

				export HADOOP_OPTS='-Djava.library.path=$HADOOP_HOME/lib/native'
				export HADOOP_COMMON_LIB_NATIVE_DIR="$HADOOP_HOME/lib/native"

				export YARN_HOME=$HADOOP_HOME
				export YARN_CONF_DIR=$HADOOP_HOME/etc/hadoop

				export JAVA_HOME=$JAVA_HOME
				export PATH=\\\$PATH:\\\$HADOOP_HOME/bin:\\\$HADOOP_HOME/sbin:\\\$SPARK_HOME/bin:\\\$SPARK_HOME/sbin:$PYTHON_VENV_PATH/bin

				export SPARK_HOME=$SPARK_HOME

			EOL"
		}

		function install_hadoop {
			echo "Extracting Hadoop to /opt/hadoop ..."
			tar -xzf /tmp/$HADOOP_FILE -C /tmp
			mv -f /tmp/$(find /tmp/ -type d -name 'hadoop-*' | head -n 1 | xargs basename) $HADOOP_HOME
			rm -f /tmp/$HADOOP_FILE

			mkdir -p /hdfs/namenode
			mkdir -p /hdfs/datanode
			chown -R $HADOOP_USER:$HADOOP_USER /hdfs
			chmod -R 700 /hdfs

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

		config_environment_variables

		install_hadoop &

		install_spark &

		wait # Wait for all background jobs to finish

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

		NAMENODE_HOSTNAME=$${NAMENODE_HOSTNAME:=namenode}
		echo "NAMENODE_HOSTNAME: $NAMENODE_HOSTNAME"

		SPARK_MASTER_HOSTNAME=$${SPARK_MASTER_HOSTNAME:=spark-master}
		echo "SPARK_MASTER_HOSTNAME: $SPARK_MASTER_HOSTNAME"

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
				    <property>
				        <name>fs.defaultFS</name>
				        <value>hdfs://$NAMENODE_HOSTNAME:9000</value>
				    </property>
				    <property>
				        <name>fs.AbstractFileSystem.gs.impl</name>
				        <value>com.google.cloud.hadoop.fs.gcs.GoogleHadoopFS</value>
				    </property>
				</configuration>
			EOL

			# Update hdfs-site.xml
			cat > $HADOOP_HOME/etc/hadoop/hdfs-site.xml <<-EOL
				<configuration>
				    <property>
				        <name>dfs.replication</name>
				        <value>2</value>
				    </property>
				    <property>
				        <name>dfs.namenode.name.dir</name>
				        <value>file:///hdfs/namenode</value>
				    </property>
				    <property>
				        <name>dfs.datanode.data.dir</name>
				        <value>file:///hdfs/datanode</value>
				    </property>
				</configuration>
			EOL

			# Update yarn-site.xml
			cat > $HADOOP_HOME/etc/hadoop/yarn-site.xml <<-EOL
				<configuration>
				    <property>
				        <name>yarn.resourcemanager.hostname</name>
				        <value>$NAMENODE_HOSTNAME</value>
				    </property>
				    <property>
				        <name>yarn.nodemanager.aux-services</name>
				        <value>mapreduce_shuffle</value>
				    </property>
				    <property>
				        <name>yarn.nodemanager.aux-services.mapreduce.shuffle.class</name>
				        <value>org.apache.hadoop.mapred.ShuffleHandler</value>
				    </property>

				    <property>
				        <name>yarn.nodemanager.resource.memory-mb</name>
				        <value>2048</value>
				    </property>
				    <property>
				        <name>yarn.scheduler.maximum-allocation-mb</name>
				        <value>2048</value>
				    </property>
				    <property>
				        <name>yarn.scheduler.minimum-allocation-mb</name>
				        <value>512</value>
				    </property>
				    <property>
				        <name>yarn.nodemanager.vmem-check-enabled</name>
				        <value>false</value>
				    </property>
				</configuration>
			EOL

			# Update mapred-site.xml
			cat > $HADOOP_HOME/etc/hadoop/mapred-site.xml <<-EOL
				<configuration>
				    <property>
				        <name>mapreduce.jobtracker.address</name>
				        <value>$NAMENODE_HOSTNAME:54311</value>
				    </property>
				    <property>
				        <name>mapreduce.framework.name</name>
				        <value>yarn</value>
				    </property>

				    <property>
				        <name>yarn.app.mapreduce.am.resource.mb</name>
				        <value>512</value>
				    </property>
				    <property>
				        <name>mapreduce.map.memory.mb</name>
				        <value>512</value>
				    </property>
				    <property>
				        <name>mapreduce.reduce.memory.mb</name>
				        <value>512</value>
				    </property>
				    <property>
				        <name>yarn.app.mapreduce.am.env</name>
				        <value>HADOOP_MAPRED_HOME=$HADOOP_HOME</value>
				    </property>
				    <property>
				        <name>mapreduce.map.env</name>
				        <value>HADOOP_MAPRED_HOME=$HADOOP_HOME</value>
				    </property>
				    <property>
				        <name>mapreduce.reduce.env</name>
				        <value>HADOOP_MAPRED_HOME=$HADOOP_HOME</value>
				    </property>
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
				export SPARK_EXECUTOR_INSTANCES=$${SPARK_EXECUTOR_INSTANCES:=1}

				export LD_LIBRARY_PATH=$HADOOP_HOME/lib/native:\\\$LD_LIBRARY_PATH
			EOL

			# Configure spark-defaults
			cat > $SPARK_HOME/conf/spark-defaults.conf <<-EOL
				spark.master             spark://$SPARK_MASTER_HOSTNAME:7077
				spark.yarn.am.memory     512m
				spark.driver.cores       $${SPARK_DRIVER_CORES:=1}
				spark.driver.memory      $${SPARK_DRIVER_MEMORY:=512m}
				spark.executor.cores     $${SPARK_EXECUTOR_CORES:=1}
				spark.executor.memory    $${SPARK_EXECUTOR_MEMORY:=2g}
		        spark.executor.instances $${SPARK_EXECUTOR_INSTANCES:=1}
				spark.serializer         org.apache.spark.serializer.KryoSerializer

				spark.eventLog.enabled          true
				spark.eventLog.dir              $${SPARK_LOG_DIR:=hdfs:/spark-events}
				spark.eventLog.compress         false
				spark.history.fs.logDirectory   $${SPARK_LOG_DIR:=hdfs:/spark-events}

		        spark.hadoop.fs.defaultFS                   hdfs://$NAMENODE_HOSTNAME:9000
		        spark.hadoop.fs.hdfs.impl                   org.apache.hadoop.hdfs.DistributedFileSystem
				spark.hadoop.fs.AbstractFileSystem.gs.impl  com.google.cloud.hadoop.fs.gcs.GoogleHadoopFS
			EOL
		}

		function start {
		    if [ "$NODE_TYPE" == "NAMENODE" ]; then
		        [ ! -f /hdfs/namenode/in_use.lock ] && hdfs namenode -format || rm -f /hdfs/namenode/in_use.lock
		        hdfs namenode

		    elif [ "$NODE_TYPE" == "DATANODE" ]; then
		        [ -f /hdfs/datanode/in_use.lock ] && rm -f /hdfs/datanode/in_use.lock
		        hdfs datanode

		    elif [ "$NODE_TYPE" == "SPARK_MASTER" ]; then
		        SPARK_NO_DAEMONIZE=true $SPARK_HOME/sbin/start-master.sh

		    elif [ "$NODE_TYPE" == "SPARK_WORKER" ]; then
		        SPARK_NO_DAEMONIZE=true $SPARK_HOME/sbin/start-worker.sh spark://$SPARK_MASTER_HOSTNAME:7077

		    elif [ "$NODE_TYPE" == "SPARK_HISTORY" ]; then
		        hdfs dfs -ls / || sleep 15 && hdfs dfs -mkdir -p /spark-events
		        SPARK_NO_DAEMONIZE=true $SPARK_HOME/sbin/start-history-server.sh

		    else
		        echo "Error: NODE_TYPE must be set to 'NAMENODE', 'DATANODE', 'SPARK_MASTER', 'SPARK_WORKER' or 'SPARK_HISTORY' "
		        exit 1

		    fi
		}

		config_hadoop
		config_spark
		start
	EOT

}

resource "local_file" "dockerfile" {
  filename = "hadoop/Dockerfile"
  content  = <<-EOT
		FROM ubuntu:kinetic as builder

		RUN apt-get -q -y update && \
			apt-get -q -y install wget ssh openjdk-11-jre

		RUN wget -P /tmp https://downloads.apache.org/hadoop/common/hadoop-${local.hadoop_version}/hadoop-${local.hadoop_version}.tar.gz && \
			wget -P /tmp https://downloads.apache.org/spark/spark-${local.spark_version}/spark-${local.spark_version}-bin-hadoop3.tgz

		COPY ${basename(local_file.public_key.filename)} /tmp/${basename(local_file.public_key.filename)}
		COPY ${basename(local_file.private_key.filename)}  /tmp/${basename(local_file.private_key.filename)}

		ENV EXTERNAL_JARS="https://repo1.maven.org/maven2/com/google/cloud/bigdataoss/gcs-connector/hadoop3-2.2.12/gcs-connector-hadoop3-2.2.12-shaded.jar \
		https://repo1.maven.org/maven2/org/mongodb/spark/mongo-spark-connector_2.12/10.1.1/mongo-spark-connector_2.12-10.1.1-all.jar \
		"

		COPY ${basename(local_file.setup.filename)} /tmp/${basename(local_file.setup.filename)}
		RUN chmod +x /tmp/${basename(local_file.setup.filename)}
		RUN /tmp/${basename(local_file.setup.filename)}

		COPY --chown=hadoop:hadoop ${basename(local_file.entrypoint.filename)} /home/hadoop/${basename(local_file.entrypoint.filename)}
		RUN chmod +x /home/hadoop/${basename(local_file.entrypoint.filename)}

		USER hadoop
		WORKDIR /home/hadoop
		CMD ["/bin/bash", "-i", "${basename(local_file.entrypoint.filename)}"]
 	 EOT

  provisioner "local-exec" {
    command = <<-EOT
		docker build -t ${local.image.name}:${local.image.tag} hadoop/
		docker push ${local.image.name}:${local.image.tag}
	EOT
  }

  lifecycle {
    replace_triggered_by = [
      local_file.private_key.id,
      local_file.public_key.id,
      local_file.entrypoint.id,
      local_file.setup.id,
    ]
  }
}

resource "local_file" "docker_compose" {
  filename = "hadoop/docker-compose.yaml"
  content  = <<-EOT
		version: '3.9'

		networks:
		  hadoop-network:
		    driver: bridge
		    ipam:
		      driver: default
		      config:
		        - subnet: 10.0.0.0/28

		services:

		  namenode:
		    image: ${local.image.name}:${local.image.tag}
		    container_name: namenode
		    hostname: namenode
		    networks:
		      hadoop-network:
		        ipv4_address: 10.0.0.3
		    ports:
		      - "9870:9870"
		    volumes:
		      - namenode-data:/hdfs/namenode
		    environment:
		      NODE_TYPE: 'NAMENODE'
		      NAMENODE_HOSTNAME: 'namenode'

		  datanode-1:
		    image: ${local.image.name}:${local.image.tag}
		    container_name: datanode-1
		    networks:
		      hadoop-network:
		        ipv4_address: 10.0.0.4
		    volumes:
		      - datanode1-hdfs:/hdfs/datanode
		    environment:
		      NODE_TYPE: 'DATANODE'
		      NAMENODE_HOSTNAME: 'namenode'

		  datanode-2:
		    image: ${local.image.name}:${local.image.tag}
		    container_name: datanode-2
		    networks:
		      hadoop-network:
		        ipv4_address: 10.0.0.5
		    volumes:
		      - datanode2-hdfs:/hdfs/datanode
		    environment:
		      NODE_TYPE: 'DATANODE'
		      NAMENODE_HOSTNAME: 'namenode'

		  spark-master:
		    image: ${local.image.name}:${local.image.tag}
		    container_name: spark-master
		    hostname: spark-master
		    networks:
		      hadoop-network:
		        ipv4_address: 10.0.0.6
		    expose: [ "7077" ]
		    ports:
		      - "8080:8080"
		    environment:
		      NODE_TYPE: 'SPARK_MASTER'
		      SPARK_MASTER_HOSTNAME: 'spark-master'

		  spark-worker-1:
		    image: ${local.image.name}:${local.image.tag}
		    container_name: spark-worker-1
		    networks:
		      hadoop-network:
		        ipv4_address: 10.0.0.7
		    environment:
		      NODE_TYPE: 'SPARK_WORKER'
		      SPARK_MASTER_HOSTNAME: 'spark-master'

		  spark-worker-2:
		    image: ${local.image.name}:${local.image.tag}
		    container_name: spark-worker-2
		    networks:
		      hadoop-network:
		        ipv4_address: 10.0.0.8
		    environment:
		      NODE_TYPE: 'SPARK_WORKER'
		      SPARK_MASTER_HOSTNAME: 'spark-master'

		  spark-history:
		    image: ${local.image.name}:${local.image.tag}
		    container_name: spark-history
		    networks:
		      hadoop-network:
		        ipv4_address: 10.0.0.9
		    ports:
		      - "18080:18080"
		    environment:
		      NODE_TYPE: 'SPARK_HISTORY'
		      NAMENODE_HOSTNAME: 'namenode'
		      SPARK_MASTER_HOSTNAME: 'spark-master'

		volumes:
		  namenode-data: {}
		  datanode1-hdfs: {}
		  datanode2-hdfs: {}
	EOT
}
