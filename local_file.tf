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

		HADOOP_USER="${local.hadoop.user}"
		HADOOP_HOME="/opt/hadoop"
		HADOOP_FILE="$(find /tmp/ -type f -name 'hadoop-*' | head -n 1 | xargs basename)"

		SPARK_HOME="/opt/spark"
		SPARK_FILE="$(find /tmp/ -type f -name 'spark-*' | head -n 1 | xargs basename)"

		PYTHON_VENV="python3"
		PYTHON_VENV_PATH="/home/$HADOOP_USER/$PYTHON_VENV"

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

		function config_environment_variables {
			su - $HADOOP_USER -c "cat > ~/.bashrc <<-EOL
				export HADOOP_HOME=$HADOOP_HOME
				export HADOOP_HDFS_HOME=$HADOOP_HOME
				export HADOOP_MAPRED_HOME=$HADOOP_HOME
				export HADOOP_COMMON_HOME=$HADOOP_HOME
				export HADOOP_CONF_DIR=$HADOOP_HOME/etc/hadoop

				export HADOOP_OPTS='-Djava.library.path=$HADOOP_HOME/lib/native'
				export HADOOP_COMMON_LIB_NATIVE_DIR="$HADOOP_HOME/lib/native"

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
			su - $HADOOP_USER -c " echo \"PATH=\$PATH:$PYTHON_VENV_PATH/bin\" >> ~/.bashrc "
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

		config_environment_variables

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

		source ~/.bashrc

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
				        <value>file:///data</value>
				    </property>
				    <property>
				        <name>dfs.datanode.data.dir</name>
				        <value>file:///data</value>
				    </property>
				    <property>
				        <name>dfs.namenode.datanode.registration.ip-hostname-check</name>
				        <value>false</value>
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
			    [ ! -f /data/current/VERSION ] && hdfs namenode -format
			    hdfs namenode

			elif [ "$NODE_TYPE" == "DATANODE" ]; then
			    hdfs datanode

			elif [ "$NODE_TYPE" == "SPARK_MASTER" ]; then
			    SPARK_NO_DAEMONIZE=true $SPARK_HOME/sbin/start-master.sh

			elif [ "$NODE_TYPE" == "SPARK_WORKER" ]; then
			    SPARK_NO_DAEMONIZE=true $SPARK_HOME/sbin/start-worker.sh spark://$SPARK_MASTER_HOSTNAME:7077

			elif [ "$NODE_TYPE" == "SPARK_HISTORY" ]; then
			    hdfs dfs -ls / || sleep 15 && hdfs dfs -mkdir -p /spark-events
			    SPARK_NO_DAEMONIZE=true $SPARK_HOME/sbin/start-history-server.sh

			elif [ "$NODE_TYPE" == "JUPYTER" ]; then
				echo "spark.driver.host $(hostname -i)" >> $SPARK_HOME/conf/spark-defaults.conf
			    jupyter lab --no-browser --config=/home/${local.hadoop.user}/.jupyter/jupyter_notebook_config.py --notebook-dir=/home/${local.hadoop.user}/jupyter

			else
			    echo "Error: NODE_TYPE must be set to 'NAMENODE', 'DATANODE', 'SPARK_MASTER', 'SPARK_WORKER', 'SPARK_HISTORY' or 'JUPYTER'"
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
		FROM ubuntu:kinetic as ${basename(local.hadoop.image.name)}${local.hadoop.image.tag}

		RUN apt-get -q -y update && \
			apt-get -q -y install wget ssh net-tools telnet curl dnsutils jq openjdk-11-jre python3 python3-venv

		RUN wget -q -P /tmp https://downloads.apache.org/hadoop/common/hadoop-${local.hadoop.version}/hadoop-${local.hadoop.version}.tar.gz && \
			wget -q -P /tmp https://downloads.apache.org/spark/spark-${local.spark.version}/spark-${local.spark.version}-bin-hadoop3.tgz

		COPY ${basename(local_file.public_key.filename)} /tmp/${basename(local_file.public_key.filename)}
		COPY ${basename(local_file.private_key.filename)}  /tmp/${basename(local_file.private_key.filename)}

		ENV EXTERNAL_JARS="${join(" ", [for lib, url in local.external_jars : url])}"

		COPY ${basename(local_file.setup.filename)} /tmp/${basename(local_file.setup.filename)}
		RUN chmod +x /tmp/${basename(local_file.setup.filename)}
		RUN /tmp/${basename(local_file.setup.filename)}

		COPY --chown=${local.hadoop.user}:${local.hadoop.user} ${basename(local_file.entrypoint.filename)} /home/${local.hadoop.user}/${basename(local_file.entrypoint.filename)}
		RUN chmod +x /home/${local.hadoop.user}/${basename(local_file.entrypoint.filename)}

		USER ${local.hadoop.user}
		WORKDIR /home/${local.hadoop.user}
		CMD ["/bin/bash", "${basename(local_file.entrypoint.filename)}"]
 	 EOT

  provisioner "local-exec" {
    # gcloud builds submit --tag ${local.hadoop.image.name}:${local.hadoop.image.tag} hadoop/ 
    command = <<-EOT
		set -e
		set -x
		docker build -t ${basename(local.hadoop.image.name)}:${local.hadoop.image.tag} ${dirname(self.filename)}
		docker tag ${basename(local.hadoop.image.name)}:${local.hadoop.image.tag} ${local.hadoop.image.name}:${local.hadoop.image.tag}
		docker push ${local.hadoop.image.name}:${local.hadoop.image.tag}
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

resource "local_file" "install_jupyter" {
  filename = "jupyter/install_jupyter.sh"
  content  = <<-EOT
		#!/bin/bash
		
		source ~/.bashrc
		
		set -e
		set -x

		HADOOP_USER="${local.hadoop.user}"
		PYTHON_VENV="python3"
		PYTHON_VENV_PATH="/home/$HADOOP_USER/$PYTHON_VENV"
		PYTHON_KERNEL=/home/$HADOOP_USER/$PYTHON_VENV/share/jupyter/kernels/python3/kernel.json
		SCALA_KERNEL=/home/$HADOOP_USER/.local/share/jupyter/kernels/apache_toree_scala/kernel.json
		
		function install_jupyterlab {
			source $PYTHON_VENV_PATH/bin/activate
										
			echo 'Installing Jupyterlab & Apache Toree ...'
			pip3 install -q jupyterlab toree ${join(" ", local.jupyter.python_libraries)}
	
			jupyter lab --generate-config
			jupyter toree install --spark_home=$SPARK_HOME --interpreters=Scala --user
	
			mkdir -p /home/$HADOOP_USER/jupyter

			echo 'Inserting Jupyter Kernel Setting ...'
			jq ".env  = { \"PATH\": \"\$PATH:$PYTHON_VENV_PATH/bin:$HADOOP_HOME/bin:$SPARK_HOME/bin\" }" $PYTHON_KERNEL > /tmp/tmp.json && mv -f /tmp/tmp.json $PYTHON_KERNEL && cat $PYTHON_KERNEL 
			jq ".env += { \"PATH\": \"\$PATH:$PYTHON_VENV_PATH/bin:$HADOOP_HOME/bin:$SPARK_HOME/bin\" }" $SCALA_KERNEL  > /tmp/tmp.json && mv -f /tmp/tmp.json $SCALA_KERNEL  && cat $SCALA_KERNEL 

			# Config Jupyter Lab Theme
			mkdir -p ~/.jupyter/lab/user-settings/@jupyterlab/apputils-extension 
			cat  >>  ~/.jupyter/lab/user-settings/@jupyterlab/apputils-extension/themes.jupyterlab-settings <<-EOL
				{ "theme": "JupyterLab Dark" }
			EOL
		
			# Config Jupyter Lab
			cat >> ~/.jupyter/jupyter_notebook_config.py <<-EOL
				c.NotebookApp.ip = '0.0.0.0'
				c.NotebookApp.port = 8888
				c.NotebookApp.open_browser = False
				c.NotebookApp.token = 'P@ssw0rd'
				c.NotebookApp.allow_origin = '*'
		
				c.MappingKernelManager.cull_idle_timeout = 8 * 60
				c.MappingKernelManager.cull_interval = 2 * 60
		
				c.RemoteKernelManager.cull_idle_timeout = 8 * 60
				c.RemoteKernelManager.cull_interval = 2 * 60
			EOL
		}

		install_jupyterlab
	EOT
}

resource "local_file" "jupyter_dockerfile" {
  depends_on = [local_file.dockerfile]
  filename   = "jupyter/Dockerfile"
  content    = <<-EOT
		FROM ${basename(local.hadoop.image.name)}:${local.hadoop.image.tag}

		USER root
		COPY ${basename(local_file.install_jupyter.filename)} /tmp/${basename(local_file.install_jupyter.filename)}
		RUN chmod +x /tmp/${basename(local_file.install_jupyter.filename)}

		USER ${local.hadoop.user}
		RUN /tmp/${basename(local_file.install_jupyter.filename)}

		WORKDIR /home/${local.hadoop.user}/
		CMD ["/bin/bash", "${basename(local_file.entrypoint.filename)}"]
 	 EOT

  provisioner "local-exec" {
    command = <<-EOT
		set -e
		set -x
		docker build -t ${basename(local.jupyter.image.name)}:${local.jupyter.image.tag} ${dirname(self.filename)}
		docker tag ${basename(local.jupyter.image.name)}:${local.jupyter.image.tag} ${local.jupyter.image.name}:${local.jupyter.image.tag}
		docker push ${local.jupyter.image.name}:${local.jupyter.image.tag}
	EOT
  }

  lifecycle {
    replace_triggered_by = [
      local_file.dockerfile.id,
      local_file.install_jupyter.id
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
		    image: ${local.hadoop.image.name}:${local.hadoop.image.tag}
		    container_name: namenode
		    hostname: namenode
		    networks:
		      hadoop-network:
		        ipv4_address: 10.0.0.3
		    ports:
		      - "9870:9870"
		    volumes:
		      - namenode-data:/data
		    environment:
		      NODE_TYPE: 'NAMENODE'
		      NAMENODE_HOSTNAME: 'namenode'

		  datanode-1:
		    image: ${local.hadoop.image.name}:${local.hadoop.image.tag}
		    container_name: datanode-1
		    networks:
		      hadoop-network:
		        ipv4_address: 10.0.0.4
		    volumes:
		      - datanode1-hdfs:/data
		    environment:
		      NODE_TYPE: 'DATANODE'
		      NAMENODE_HOSTNAME: 'namenode'

		  datanode-2:
		    image: ${local.hadoop.image.name}:${local.hadoop.image.tag}
		    container_name: datanode-2
		    networks:
		      hadoop-network:
		        ipv4_address: 10.0.0.5
		    volumes:
		      - datanode2-hdfs:/data
		    environment:
		      NODE_TYPE: 'DATANODE'
		      NAMENODE_HOSTNAME: 'namenode'

		  spark-master:
		    image: ${local.hadoop.image.name}:${local.hadoop.image.tag}
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
		    image: ${local.hadoop.image.name}:${local.hadoop.image.tag}
		    container_name: spark-worker-1
		    networks:
		      hadoop-network:
		        ipv4_address: 10.0.0.7
		    environment:
		      NODE_TYPE: 'SPARK_WORKER'
		      SPARK_MASTER_HOSTNAME: 'spark-master'

		  spark-worker-2:
		    image: ${local.hadoop.image.name}:${local.hadoop.image.tag}
		    container_name: spark-worker-2
		    networks:
		      hadoop-network:
		        ipv4_address: 10.0.0.8
		    environment:
		      NODE_TYPE: 'SPARK_WORKER'
		      SPARK_MASTER_HOSTNAME: 'spark-master'

		  spark-history:
		    image: ${local.hadoop.image.name}:${local.hadoop.image.tag}
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


