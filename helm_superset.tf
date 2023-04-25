data "http" "superset_values_yaml" {
  url = "https://raw.githubusercontent.com/apache/superset/master/helm/superset/values.yaml"
}

resource "helm_release" "superset" {
  name             = "superset"
  repository       = "http://apache.github.io/superset"
  chart            = "superset"
  namespace        = "superset"
  create_namespace = true

  values = [data.http.superset_values_yaml.response_body]

  set {
    name  = "bootstrapScript"
    value = <<-EOT
		#!/bin/bash
		pip3 install pyodbc JPype1
		pip3 install sqlalchemy-drill
	EOT
  }

  set_sensitive {
    name  = "adminUser.password"
    value = var.superset_password
  }

  cleanup_on_fail = true
  wait_for_jobs   = true
  timeout         = 600
}