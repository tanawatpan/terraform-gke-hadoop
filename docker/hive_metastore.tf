resource "local_file" "hive_metastore_entrypoint" {
  filename = "hive-metastore/entrypoint.sh"
  content  = <<-EOT
		#!/bin/bash

		set -e
		set -x

		function create_property() {
			cat <<-EOL
			    <property>
			        <name>$1</name>
			        <value>$2</value>
			    </property>
			EOL
		}
		
		function create_hive_metastore_configuration() {
		    cat > $HIVE_HOME/conf/metastore-site.xml <<-EOF
				<configuration>
					$(create_property metastore.thrift.uris         thrift://0.0.0.0:9083 )
					$(create_property fs.defaultFS                  hdfs://$${NAMENODE_HOSTNAME}:9000 )
					$(create_property metastore.warehouse.dir       hdfs://$${NAMENODE_HOSTNAME}:9000/$${HIVE_WAREHOUSE:=/user/hive/warehouse} )
					$(create_property metastore.task.threads.always org.apache.hadoop.hive.metastore.events.EventCleanerTask,org.apache.hadoop.hive.metastore.MaterializationsCacheCleanerTask )
					$(create_property metastore.expression.proxy    org.apache.hadoop.hive.metastore.DefaultPartitionExpressionProxy )
		
					$(create_property javax.jdo.option.ConnectionDriverName com.mysql.cj.jdbc.Driver )
					$(create_property javax.jdo.option.ConnectionURL        jdbc:mysql://$${DATABASE_HOST}:$${DATABASE_PORT}/$${DATABASE_DB} )
					$(create_property javax.jdo.option.ConnectionUserName   $DATABASE_USER )
					$(create_property javax.jdo.option.ConnectionPassword   $DATABASE_PASSWORD )
		
					$(create_property fs.s3a.endpoint   $S3_ENDPOINT_URL )
					$(create_property fs.s3a.access.key $S3_ACCESS_KEY_ID )
					$(create_property fs.s3a.secret.key $S3_SECRET_ACCESS_KEY )
					$(create_property fs.s3a.impl                   org.apache.hadoop.fs.s3a.S3AFileSystem )
					$(create_property fs.s3a.fast.upload            true )
					$(create_property fs.s3a.path.style.access      true )
					$(create_property fs.s3a.connection.ssl.enabled false )
				</configuration>
			EOF
		}
		
		function create_hadoop_core_configuration() {
			cat > $HADOOP_HOME/etc/hadoop/core-site.xml <<-EOF
				<configuration>
					$(create_property fs.defaultFS					hdfs://$NAMENODE_HOSTNAME:9000 )
					$(create_property fs.AbstractFileSystem.gs.impl com.google.cloud.hadoop.fs.gcs.GoogleHadoopFS )
					$(create_property hadoop.proxyuser.hue.hosts	"*" )
					$(create_property hadoop.proxyuser.hue.groups	"*" )
					$(create_property hadoop.proxyuser.trino.hosts	"*" )
					$(create_property hadoop.proxyuser.trino.groups	"*" )
				</configuration>
			EOF
		}
		
		create_hive_metastore_configuration
		create_hadoop_core_configuration
		
		if $HIVE_HOME/bin/schematool -dbType mysql -info | grep -q "Metastore schema version"; then
		  echo "Hive Metastore schema already exists"
		else
		  echo "Hive Metastore schema does not exist. Initializing schema"
		  $HIVE_HOME/bin/schematool -dbType mysql -initSchema
		fi

		$HIVE_HOME/bin/start-metastore
	EOT
}

resource "local_file" "hive_metastore_dockerfile" {
  filename = "hive-metastore/Dockerfile"
  content  = <<-EOT
		FROM ubuntu:kinetic as ${basename(local.hive_metastore.image.name)}-${local.hive_metastore.image.tag}
		
		RUN apt-get update \
		 && apt-get install --assume-yes curl wget ssh net-tools telnet dnsutils jq openjdk-11-jre \
		 && apt-get clean
		
		ARG HADOOP_VERSION=${local.hadoop.version}
		ARG HADOOP_URL=https://archive.apache.org/dist/hadoop/common/hadoop-$${HADOOP_VERSION}/hadoop-$${HADOOP_VERSION}.tar.gz
		
		ARG HIVE_METASTORE_VERSION=${local.hive_metastore.version}
		ARG HIVE_METASTORE_URL=https://apache.org/dist/hive/hive-standalone-metastore-$${HIVE_METASTORE_VERSION}/hive-standalone-metastore-$${HIVE_METASTORE_VERSION}-bin.tar.gz
		
		ARG MYSQL_CONNECTOR_VERSION=8.0.33
		ARG MYSQL_CONNECTOR_URL=https://dev.mysql.com/get/Downloads/Connector-J/mysql-connector-j-$${MYSQL_CONNECTOR_VERSION}.tar.gz
		
		ENV JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64
		ENV HADOOP_HOME=/opt/hadoop
		ENV HIVE_HOME=/opt/hive-metastore

		WORKDIR /tmp 
		RUN curl -L $HADOOP_URL | tar zxf - && mv -f $(find ./ -type d -name 'hadoop-*' | head -n 1 | xargs basename) $HADOOP_HOME 
		RUN curl -L $HIVE_METASTORE_URL  | tar zxf - && mv -f $(find ./ -type d -name 'apache-hive-*' | head -n 1 | xargs basename) $HIVE_HOME 
		RUN curl -L $MYSQL_CONNECTOR_URL | tar zxf - && mv -f $(find ./ -type f -name 'mysql-connector-j-*.jar' | head -n 1 ) $HIVE_HOME/lib/ 
		RUN ln -s $HADOOP_HOME/share/hadoop/tools/lib/hadoop-aws-*    $HADOOP_HOME/share/hadoop/common/lib/ \
		 && ln -s $HADOOP_HOME/share/hadoop/tools/lib/aws-java-sdk-*  $HADOOP_HOME/share/hadoop/common/lib/ \
		 && rm $HIVE_HOME/lib/guava-19.0.jar && cp $HADOOP_HOME/share/hadoop/hdfs/lib/guava-27.0-jre.jar $HIVE_HOME/lib/ # https://issues.apache.org/jira/browse/HIVE-22915
		
		RUN groupadd -r hive --gid=1000 \
		 && useradd -r -g hive --uid=1000 -d $HIVE_HOME hive \
		 && chown hive:hive -R $HADOOP_HOME \
		 && chown hive:hive -R $HIVE_HOME

		USER hive
		WORKDIR /home/hive/
		COPY --chown=hive:hive ${basename(local_file.hive_metastore_entrypoint.filename)} ${basename(local_file.hive_metastore_entrypoint.filename)}
		CMD ["/bin/bash", "${basename(local_file.hive_metastore_entrypoint.filename)}"]
 	 EOT

  provisioner "local-exec" {
    command = <<-EOT
		set -x
		set -e
		docker build --platform linux/amd64 -t ${basename(local.hive_metastore.image.name)}:${local.hive_metastore.image.tag} ${dirname(self.filename)}
		docker tag ${basename(local.hive_metastore.image.name)}:${local.hive_metastore.image.tag} ${local.hive_metastore.image.name}:${local.hive_metastore.image.tag}
		docker push ${local.hive_metastore.image.name}:${local.hive_metastore.image.tag}
	EOT
  }

  lifecycle {
    replace_triggered_by = [
      local_file.hive_metastore_entrypoint.id,
    ]
  }
}
