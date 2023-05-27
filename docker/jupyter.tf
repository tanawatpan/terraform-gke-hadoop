resource "local_file" "install_jupyter" {
  filename = "jupyter/install_jupyter.sh"
  content  = <<-EOT
		#!/bin/bash
		
		set -e
		set -x
		
		function install_jupyterlab {
			curl https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh -o Miniconda3-latest-Linux-x86_64.sh
			bash Miniconda3-latest-Linux-x86_64.sh -b
			./miniconda3/bin/conda init
			eval "$(./miniconda3/bin/conda shell.bash hook)"

			conda create --yes --name jupyter python=${local.jupyter.python.version}
			echo 'conda activate jupyter' >> ~/.bashrc
			conda activate jupyter

			conda install --yes -c conda-forge cudatoolkit=11.8.0
			python3 -m pip install nvidia-cudnn-cu11==8.6.0.163 tensorflow==2.12.*
			mkdir -p $CONDA_PREFIX/etc/conda/activate.d
			echo 'CUDNN_PATH=$(dirname $(python -c "import nvidia.cudnn;print(nvidia.cudnn.__file__)"))' >> $CONDA_PREFIX/etc/conda/activate.d/env_vars.sh
			echo 'export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:$CONDA_PREFIX/lib/:$CUDNN_PATH/lib' >> $CONDA_PREFIX/etc/conda/activate.d/env_vars.sh
										
			echo 'Installing Jupyterlab & Apache Toree ...'
			pip3 install -q jupyterlab==${local.jupyter.version} toree ${join(" ", local.jupyter.python.libraries)}

			wget https://git.io/coursier-cli
			chmod +x coursier-cli
			./coursier-cli launch --fork almond:${local.jupyter.almond.version} --scala ${local.jupyter.almond.scala_version} -- --install
	
			jupyter lab --generate-config
			jupyter toree install --spark_home=$SPARK_HOME --interpreters=Scala --user
	
			mkdir -p /home/$HADOOP_USER/notebooks

			PYTHON_KERNEL=$CONDA_PREFIX/share/jupyter/kernels/python3/kernel.json
			TOREE_SCALA_KERNEL=/home/$HADOOP_USER/.local/share/jupyter/kernels/apache_toree_scala/kernel.json
			SCALA_KERNEL=/home/$HADOOP_USER/.local/share/jupyter/kernels/scala/kernel.json

			echo 'Inserting Jupyter Kernel Setting ...'
			jq ".env  = { \"PATH\": \"\$PATH:$PYTHON_VENV_PATH/bin:$HADOOP_HOME/bin:$SPARK_HOME/bin\" }" $PYTHON_KERNEL > /tmp/tmp.json && mv -f /tmp/tmp.json $PYTHON_KERNEL && cat $PYTHON_KERNEL 
			jq ".env += { \"PATH\": \"\$PATH:$PYTHON_VENV_PATH/bin:$HADOOP_HOME/bin:$SPARK_HOME/bin\" }" $TOREE_SCALA_KERNEL  > /tmp/tmp.json && mv -f /tmp/tmp.json $TOREE_SCALA_KERNEL  && cat $TOREE_SCALA_KERNEL 
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
			$CONDA_PREFIX/bin/jupyter lab --no-browser --config=/home/$HADOOP_USER/.jupyter/jupyter_notebook_config.py --notebook-dir=/home/$HADOOP_USER/notebooks
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
		FROM ${local.spark.image_name}:${local.spark.version}

		RUN echo "${basename(local.jupyter.image_name)}:${local.jupyter.version}" > /tmp/image_name

		USER root
		COPY ${basename(local_file.install_jupyter.filename)} /tmp/${basename(local_file.install_jupyter.filename)}
		RUN chmod +x /tmp/${basename(local_file.install_jupyter.filename)}
		
		USER $HADOOP_USER
		RUN /tmp/${basename(local_file.install_jupyter.filename)}

		ENV PATH=/home/$HADOOP_USER/miniconda3/bin/:$PATH

		WORKDIR /home/$HADOOP_USER
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
