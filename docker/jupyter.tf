resource "local_file" "install_jupyter" {
  filename = "jupyter/install_jupyter.sh"
  content  = <<-EOT
		#!/bin/bash
		
		set -e
		set -x
		
		function install_jupyterlab {
			curl https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh -o ./Miniconda3-latest-Linux-x86_64.sh
			bash ./Miniconda3-latest-Linux-x86_64.sh -b
			~/miniconda3/bin/conda init
			eval "$(./miniconda3/bin/conda shell.bash hook)"

			conda create --yes --name jupyter python=${local.jupyter.python.version}
			echo 'conda activate jupyter' >> ~/.bashrc
			conda activate jupyter

			pip3 install -q jupyterlab==${local.jupyter.version} toree ${join(" ", local.jupyter.python.libraries)}

			jupyter lab --generate-config
			jupyter toree install --spark_home=$SPARK_HOME --interpreters=Scala --user

			mkdir -p /home/$HADOOP_USER/notebooks

			PYTHON_KERNEL=$CONDA_PREFIX/share/jupyter/kernels/python3/kernel.json
			TOREE_SCALA_KERNEL=/home/$HADOOP_USER/.local/share/jupyter/kernels/apache_toree_scala/kernel.json
			
			mv $PYTHON_KERNEL      $${PYTHON_KERNEL}_bk      && jq ".env  = { \"PATH\": \"\$PATH:$PYTHON_VENV_PATH/bin:$HADOOP_HOME/bin:$SPARK_HOME/bin\" }" $${PYTHON_KERNEL}_bk > $PYTHON_KERNEL 
			mv $TOREE_SCALA_KERNEL $${TOREE_SCALA_KERNEL}_bk && jq ".env += { \"PATH\": \"\$PATH:$PYTHON_VENV_PATH/bin:$HADOOP_HOME/bin:$SPARK_HOME/bin\" }" $${TOREE_SCALA_KERNEL}_bk  > $TOREE_SCALA_KERNEL 

			mkdir -p ~/.jupyter/lab/user-settings/@jupyterlab/apputils-extension 
			echo '{ "theme": "JupyterLab Dark" }' >>  ~/.jupyter/lab/user-settings/@jupyterlab/apputils-extension/themes.jupyterlab-settings
		}

		install_jupyterlab
	EOT
}

resource "local_file" "jupyter_entrypoint" {
  filename = "jupyter/jupyter-entrypoint.sh"
  content  = <<-EOT
		#!/bin/bash

		set -e
		set -x

		eval "$(./miniconda3/bin/conda shell.bash hook)"
		conda activate jupyter

		source /home/$HADOOP_USER/config.sh

		HASHED_PASSWORD=$(python3 -c "from IPython.lib import passwd; print(passwd('$JUPYTER_PASSWORD'))")

		function config_jupyter {
			# Config Jupyter Lab
			cat >> ~/.jupyter/jupyter_notebook_config.py <<-EOL
				c.ServerApp.ip = '0.0.0.0'
				c.ServerApp.port = 8888
				c.ServerApp.allow_origin = '*'
				c.NotebookApp.password = "$HASHED_PASSWORD"
				c.NotebookApp.open_browser = False
		
				c.MappingKernelManager.cull_idle_timeout = $${CULL_IDLE_TIMEOUT:=600}
				c.MappingKernelManager.cull_interval = $${CULL_INTERVAL:=120}
		
				c.RemoteKernelManager.cull_idle_timeout = $${CULL_IDLE_TIMEOUT:=600}
				c.RemoteKernelManager.cull_interval =  $${CULL_INTERVAL:=120}

				c.LabServerApp.notebook_starts_kernel = False
			EOL
		}

		function start {
			echo "spark.driver.host $(hostname -i)" >> $SPARK_HOME/conf/spark-defaults.conf
			$CONDA_PREFIX/bin/jupyter lab --no-browser --config=/home/$HADOOP_USER/.jupyter/jupyter_notebook_config.py --notebook-dir=/home/$HADOOP_USER/notebooks
		}

		config_hadoop
		config_spark
		config_jupyter
		start
	EOT
}

resource "local_file" "jupyter_dockerfile" {
  depends_on = [google_artifact_registry_repository.repository, local_file.spark_dockerfile]
  filename   = "jupyter/Dockerfile"
  content    = <<-EOT
		FROM ${local.spark.image_name}:${local.spark.version} as builder

		FROM tensorflow/tensorflow:latest-gpu

		RUN echo "${basename(local.jupyter.image_name)}:${local.jupyter.version}" 

		RUN apt-get -q -y update \
		 && apt-get -q -y install wget ssh net-tools telnet curl dnsutils jq openjdk-11-jre

		RUN curl -L -o jq https://github.com/jqlang/jq/releases/download/jq-1.6/jq-linux64 \
		 && chmod +x jq \
		 && mv jq /usr/local/bin/jq

		ENV JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64

		ENV HADOOP_USER="${local.hadoop.user}"
		ENV HADOOP_HOME=/opt/hadoop
		ENV HADOOP_CONF_DIR=$HADOOP_HOME/etc/hadoop
		ENV HADOOP_OPTS='-Djava.library.path=$HADOOP_HOME/lib/native'
		ENV HADOOP_COMMON_LIB_NATIVE_DIR="$HADOOP_HOME/lib/native"

		ENV SPARK_HOME=/opt/spark
		ENV PATH=$SPARK_HOME/bin:$SPARK_HOME/sbin:$HADOOP_HOME/bin:$HADOOP_HOME/sbin:$PATH

		RUN groupadd -r $HADOOP_USER --gid=1000 \
			&& useradd -r -g $HADOOP_USER --uid=1000 -m $HADOOP_USER \
			&& usermod -a -G root $HADOOP_USER \
			&& chmod g+w /etc

		COPY --chown=$HADOOP_USER:$HADOOP_USER --from=builder /home/$HADOOP_USER/.ssh/ /home/$HADOOP_USER/.ssh/
		COPY --chown=$HADOOP_USER:$HADOOP_USER --from=builder $HADOOP_HOME $HADOOP_HOME
		COPY --chown=$HADOOP_USER:$HADOOP_USER --from=builder $SPARK_HOME  $SPARK_HOME

		USER $HADOOP_USER
		WORKDIR /home/$HADOOP_USER
		COPY --chown=$HADOOP_USER:$HADOOP_USER ${basename(local_file.install_jupyter.filename)} /tmp/${basename(local_file.install_jupyter.filename)}
		RUN chmod +x /tmp/${basename(local_file.install_jupyter.filename)}
		RUN /tmp/${basename(local_file.install_jupyter.filename)}

		ENV PATH=/home/$HADOOP_USER/miniconda3/bin/:$PATH

		COPY --chown=$HADOOP_USER:$HADOOP_USER --from=builder /home/$HADOOP_USER/config.sh .
		COPY --chown=$HADOOP_USER:$HADOOP_USER ${basename(local_file.jupyter_entrypoint.filename)} ${basename(local_file.jupyter_entrypoint.filename)}
		CMD ["/bin/bash", "${basename(local_file.jupyter_entrypoint.filename)}"]
 	 EOT

  provisioner "local-exec" {
    command = <<-EOT
		gcloud builds submit --tag ${local.jupyter.image_name}:${local.jupyter.version} ${dirname(self.filename)}
	EOT
  }

  lifecycle {
    replace_triggered_by = [
      local_file.spark_dockerfile.content,
      local_file.install_jupyter.content,
      local_file.jupyter_entrypoint.content,
    ]
  }
}
