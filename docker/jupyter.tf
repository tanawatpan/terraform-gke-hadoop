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
  depends_on = [local_file.hadoop_dockerfile]
  filename   = "jupyter/Dockerfile"
  content    = <<-EOT
		FROM ${basename(local.hadoop.image.name)}:${local.hadoop.image.tag} as ${basename(local.jupyter.image.name)}-${local.jupyter.image.tag}

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
		set -x
		set -e
		docker build --platform linux/amd64 -t ${basename(local.jupyter.image.name)}:${local.jupyter.image.tag} ${dirname(self.filename)}
		docker tag ${basename(local.jupyter.image.name)}:${local.jupyter.image.tag} ${local.jupyter.image.name}:${local.jupyter.image.tag}
		docker push ${local.jupyter.image.name}:${local.jupyter.image.tag}
	EOT
  }

  lifecycle {
    replace_triggered_by = [
      local_file.hadoop_dockerfile.id,
      local_file.install_jupyter.id
    ]
  }
}
