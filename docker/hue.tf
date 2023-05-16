resource "local_file" "hue_dockerfile" {
  filename = "hue/Dockerfile"
  content  = <<-EOT
		FROM gethue/hue:${local.hue.version}
		RUN ./build/env/bin/pip install thrift_sasl && \
			./build/env/bin/pip install pyhive
 	 EOT

  provisioner "local-exec" {
    command = <<-EOT
		set -x
		set -e
		docker build --platform linux/amd64 -t ${basename(local.hue.image_name)}:${local.hue.version} ${dirname(self.filename)}
		docker tag ${basename(local.hue.image_name)}:${local.hue.version} ${local.hue.image_name}:${local.hue.version}
		docker push ${local.hue.image_name}:${local.hue.version}
	EOT
  }
}
