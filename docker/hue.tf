resource "local_file" "hue_dockerfile" {
  depends_on = [google_artifact_registry_repository.repository]
  filename   = "hue/Dockerfile"
  content    = <<-EOT
		FROM gethue/hue:${local.hue.version}
		RUN ./build/env/bin/pip install thrift_sasl && \
			./build/env/bin/pip install pyhive
 	 EOT

  provisioner "local-exec" {
    command = <<-EOT
		gcloud builds submit --tag ${local.hue.image_name}:${local.hue.version} ${dirname(self.filename)}
	EOT
  }
}
