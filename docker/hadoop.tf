resource "local_file" "install_hadoop" {
  filename = "hadoop/install-hadoop.sh"
  content  = <<-EOT
		#!/bin/bash

		set -e
		set -x

		HADOOP_FILE="$(find /tmp/ -type f -name 'hadoop-*' | head -n 1 | xargs basename)"

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

			# Hadoop configuration
			cat >> $HADOOP_HOME/etc/hadoop/hadoop-env.sh <<-EOL
				export HADOOP_OPTS='-Djava.library.path=$HADOOP_HOME/lib/native'
				export HADOOP_COMMON_LIB_NATIVE_DIR="$HADOOP_HOME/lib/native"
				export JAVA_HOME=$JAVA_HOME
			EOL
		}

		function create_hadoop_configuration_script {
			su - $HADOOP_USER -c "touch /home/$HADOOP_USER/config.sh"
			cat >> /home/$HADOOP_USER/config.sh <<-'EOF'
				#!/bin/bash

				function create_property() {
					cat <<-EOL
						<property>
						    <name>$1</name>
						    <value>$2</value>
						</property>
					EOL
				}

				function config_hadoop {
					# Update core-site.xml
					cat > $HADOOP_HOME/etc/hadoop/core-site.xml <<-EOL
						<configuration>
							$(create_property fs.defaultFS					hdfs://$NAMENODE_HOSTNAME:9000 )
							$(create_property fs.gs.impl					com.google.cloud.hadoop.fs.gcs.GoogleHadoopFileSystem )
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

			EOF
		}

		create_user

		install_hadoop

		create_hadoop_configuration_script

		echo "Finished installing Hadoop."
	EOT
}

resource "local_file" "hadoop_entrypoint" {
  filename = "hadoop/hadoop-entrypoint.sh"
  content  = <<-EOT
		#!/bin/bash

		set -e
		set -x

		source /home/$HADOOP_USER/config.sh

		NODE_TYPE=$${NODE_TYPE^^}
		echo "NODE_TYPE: $NODE_TYPE"

		function start {
			if [ "$NODE_TYPE" == "NAMENODE" ]; then
			    [ ! -f /data/current/VERSION ] && hdfs namenode -format
			    hdfs namenode

			elif [ "$NODE_TYPE" == "DATANODE" ]; then
			    hdfs datanode

			else
			    echo "Error: NODE_TYPE must be set to 'NAMENODE', 'DATANODE' "
			    exit 1

			fi
		}

		config_hadoop
		start
	EOT
}

resource "local_file" "hadoop_dockerfile" {
  filename = "hadoop/Dockerfile"
  content  = <<-EOT
		FROM ubuntu:kinetic

		RUN echo "${basename(local.hadoop.image_name)}-${local.hadoop.version}"

		RUN apt-get -q -y update && \
			apt-get -q -y install wget ssh net-tools telnet curl dnsutils jq openjdk-11-jre python3 python3-venv

		RUN wget -q -P /tmp https://downloads.apache.org/hadoop/common/hadoop-${local.hadoop.version}/hadoop-${local.hadoop.version}.tar.gz 

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
		ENV PATH=$HADOOP_HOME/bin:$HADOOP_HOME/sbin:$PATH

		COPY ${basename(local_file.install_hadoop.filename)} /tmp/${basename(local_file.install_hadoop.filename)}
		RUN chmod +x /tmp/${basename(local_file.install_hadoop.filename)}
		RUN /tmp/${basename(local_file.install_hadoop.filename)}

		USER $HADOOP_USER
		WORKDIR /home/$HADOOP_USER
		COPY --chown=$HADOOP_USER:$HADOOP_USER ${basename(local_file.hadoop_entrypoint.filename)} ${basename(local_file.hadoop_entrypoint.filename)}
		CMD ["/bin/bash", "${basename(local_file.hadoop_entrypoint.filename)}"]
 	 EOT

  provisioner "local-exec" {
    # gcloud builds submit --tag ${local.hadoop.image_name}:${local.hadoop.version} hadoop/ 
    command = <<-EOT
		set -x
		set -e
		docker build --platform linux/amd64 -t ${basename(local.hadoop.image_name)}:${local.hadoop.version} ${dirname(self.filename)}
		docker tag ${basename(local.hadoop.image_name)}:${local.hadoop.version} ${local.hadoop.image_name}:${local.hadoop.version}
		docker push ${local.hadoop.image_name}:${local.hadoop.version}
	EOT
  }

  lifecycle {
    replace_triggered_by = [
      local_file.private_key.content,
      local_file.public_key.content,
      local_file.hadoop_entrypoint.content,
      local_file.install_hadoop.content,
    ]
  }
}
