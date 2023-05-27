resource "kubernetes_service_v1" "jupyter" {
  metadata {
    name      = "jupyter"
    namespace = kubernetes_namespace.hadoop.metadata.0.name
  }

  spec {
    type = "NodePort"

    port {
      port        = 8888
      target_port = 8888
    }

    selector = {
      app = "jupyter"
    }
  }

  lifecycle {
    ignore_changes = [
      metadata.0.annotations,
    ]
  }
}

data "http" "nvidia_driver_installer_manifest" {
  url = "https://raw.githubusercontent.com/GoogleCloudPlatform/container-engine-accelerators/master/nvidia-driver-installer/cos/daemonset-preloaded.yaml"
}

resource "kubectl_manifest" "nvidia_driver_installer" {
  yaml_body        = data.http.nvidia_driver_installer_manifest.response_body
  wait_for_rollout = true
}

resource "kubernetes_pod_v1" "jupyter" {
  metadata {
    name      = "jupyter"
    namespace = kubernetes_namespace.hadoop.metadata.0.name
    labels = {
      app = "jupyter"
    }
  }

  spec {
    service_account_name = kubernetes_service_account.storage_admin.metadata.0.name

    node_selector = {
      "cloud.google.com/gke-nodepool" = coalesce([for pool in data.google_container_cluster.cluster.node_pool : pool.name if length(pool.node_config.0.guest_accelerator) > 0].0, "")
    }

    init_container {
      name  = "change-volume-owner"
      image = "busybox:latest"

      command = [
        "/bin/sh",
        "-c",
        "rm -rf /home/${local.hadoop.user}/jupyter/lost+found && chown -R 1000:1000 /home/${local.hadoop.user}/jupyter",
      ]

      volume_mount {
        mount_path = "/home/${local.hadoop.user}/jupyter"
        name       = kubernetes_persistent_volume_claim.jupyter_notebooks.metadata.0.name
      }
    }

    container {
      name    = "jupyter"
      image   = "${local.jupyter.image_name}:${local.jupyter.version}"
      command = ["/bin/bash", "-c", "eval \"$(./miniconda3/bin/conda shell.bash hook)\" && sed -i 's/PYTHON_VENV_PATH/CONDA_PREFIX/g' ./jupyter-entrypoint.sh && ./miniconda3/bin/conda activate jupyter && ./jupyter-entrypoint.sh"]
      # command = ["/bin/bash", "-c", "/home/hadoop/python3/bin/pip install pyarrow scikit-learn wordcloud spark-nlp && /home/hadoop/python3/bin/pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cpu && /home/hadoop/python3/bin/pip install ckip-transformers && sed -i 's/PYTHON_VENV_PATH/CONDA_PREFIX/g' ./jupyter-entrypoint.sh && ./miniconda3/bin/conda activate jupyter && ./jupyter-entrypoint.sh"]

      env {
        name  = "NAMENODE_HOSTNAME"
        value = "${kubernetes_service_v1.namenode.metadata.0.name}-0.${kubernetes_service_v1.namenode.metadata.0.name}.${kubernetes_service_v1.namenode.metadata.0.namespace}.svc.cluster.local"
      }

      env {
        name  = "SPARK_MASTER_HOSTNAME"
        value = kubernetes_service_v1.spark_master.metadata.0.name
      }

      env {
        name  = "SPARK_DRIVER_MEMORY"
        value = "4g"
      }

      env {
        name  = "HIVE_METASTORE_HOSTNAME"
        value = "${kubernetes_service_v1.hive_metastore.metadata.0.name}.${kubernetes_service_v1.hive_metastore.metadata.0.namespace}.svc.cluster.local"
      }

      env {
        name  = "HIVE_WAREHOUSE"
        value = local.hive_metastore.warehouse
      }

      port {
        container_port = 8888
      }

      readiness_probe {
        http_get {
          path = "/login"
          port = "8888"
        }

        initial_delay_seconds = 60
        period_seconds        = 10
      }

      volume_mount {
        mount_path = "/home/${local.hadoop.user}/notebooks"
        name       = kubernetes_persistent_volume_claim.jupyter_notebooks.metadata.0.name
      }

      resources {
        limits = {
          "nvidia.com/gpu" = "1"
        }
      }
    }

    volume {
      name = kubernetes_persistent_volume_claim.jupyter_notebooks.metadata.0.name
      persistent_volume_claim {
        claim_name = kubernetes_persistent_volume_claim.jupyter_notebooks.metadata.0.name
      }
    }
  }
}

resource "kubernetes_persistent_volume_claim" "jupyter_notebooks" {
  wait_until_bound = false

  metadata {
    name      = "jupyter-notebooks"
    namespace = kubernetes_namespace.hadoop.metadata.0.name
  }

  spec {
    storage_class_name = "standard-rwo"
    access_modes       = ["ReadWriteOnce"]
    resources {
      requests = {
        storage = "1Gi"
      }
    }
  }
}


