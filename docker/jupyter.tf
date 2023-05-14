resource "local_file" "install_jupyter" {
  filename = "jupyter/install_jupyter.sh"
  content  = <<-EOT
		#!/bin/bash
		
		set -e
		set -x

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

		source /home/$HADOOP_USER/config.sh

		function config_jupyter {
			# Config Jupyter Lab
			cat >> ~/.jupyter/jupyter_notebook_config.py <<-EOL
				c.ServerApp.ip = '0.0.0.0'
				c.ServerApp.port = 8888
				c.ServerApp.allow_origin = '*'
				c.IdentityProvider.token = "$${JUPYTER_PWD:=P@ssw0rd}"
				c.NotebookApp.open_browser = False
		
				c.MappingKernelManager.cull_idle_timeout = 8 * 60
				c.MappingKernelManager.cull_interval = 2 * 60
		
				c.RemoteKernelManager.cull_idle_timeout = 8 * 60
				c.RemoteKernelManager.cull_interval = 2 * 60

				c.LabServerApp.notebook_starts_kernel = False
			EOL
		}

		function start {
			echo "spark.driver.host $(hostname -i)" >> $SPARK_HOME/conf/spark-defaults.conf
			$PYTHON_VENV_PATH/bin/jupyter lab --no-browser --config=/home/$HADOOP_USER/.jupyter/jupyter_notebook_config.py --notebook-dir=/home/$HADOOP_USER/jupyter
		}

		config_hadoop
		config_spark
		config_jupyter
		start
	EOT
}

resource "local_file" "jupyter_dockerfile" {
  depends_on = [local_file.spark_dockerfile]
  filename   = "jupyter/Dockerfile"
  content    = <<-EOT
		FROM ${basename(local.spark.image.name)}:${local.spark.image.tag}

		USER root
		COPY ${basename(local_file.install_jupyter.filename)} /tmp/${basename(local_file.install_jupyter.filename)}
		RUN chmod +x /tmp/${basename(local_file.install_jupyter.filename)}
		
		USER $HADOOP_USER
		RUN /tmp/${basename(local_file.install_jupyter.filename)}

		WORKDIR /home/$HADOOP_USER
		COPY --chown=$HADOOP_USER:$HADOOP_USER ${basename(local_file.jupyter_entrypoint.filename)} ${basename(local_file.jupyter_entrypoint.filename)}
		CMD ["/bin/bash", "${basename(local_file.jupyter_entrypoint.filename)}"]
 	 EOT

  provisioner "local-exec" {
    command = <<-EOT
		set -x
		set -e
		docker build --platform linux/amd64 -t ${basename(local.jupyter.image.name)}:${local.jupyter.image.tag} ${dirname(self.filename)}
		docker tag ${basename(local.jupyter.image.name)}:${local.jupyter.image.tag} ${local.jupyter.image.name}:${local.jupyter.image.tag}
		docker push ${local.jupyter.image.name}:${local.jupyter.image.tag}
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
