data "http" "trino_values_yaml" {
  url = "https://raw.githubusercontent.com/trinodb/charts/main/charts/trino/values.yaml"
}

resource "helm_release" "trino" {
  name             = "trino"
  repository       = "https://trinodb.github.io/charts"
  chart            = "trino"
  namespace        = "trino"
  create_namespace = true

  values = [data.http.trino_values_yaml.response_body]

  set {
    name  = "server.workers"
    value = 2
  }

  cleanup_on_fail = true
  wait_for_jobs   = true
  timeout         = 600
}
