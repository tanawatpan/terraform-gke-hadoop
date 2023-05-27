variable "project" {
  type        = string
  description = "Google Cloud project ID"

  validation {
    condition     = length(var.project) > 0
    error_message = "The project ID must not be empty."
  }
}

variable "region" {
  type        = string
  description = "Google Cloud deployment region"

  validation {
    condition     = can(regex("^([a-z]+-[a-z]+[1-9])$", var.region))
    error_message = "The region must follow Google Cloud's naming convention (e.g., 'us-central1')."
  }
}

variable "zone" {
  type        = string
  description = "Google Cloud deployment zone"

  validation {
    condition     = can(regex("^([a-z]+-[a-z]+[1-9]-[a-z])$", var.zone))
    error_message = "The zone must follow Google Cloud's naming convention (e.g., 'us-central1-a')."
  }
}

variable "cluster_name" {
  type        = string
  description = "Name of the GKE cluster"
}

variable "primary_node_count" {
  type        = number
  description = "Number of nodes in the primary node pool"
  default     = 1
}

variable "primary_machine_type" {
  type        = string
  description = "Machine type for the primary node pool"
  default     = "n1-standard-8"
}

variable "primary_disk_size_gb" {
  type        = number
  description = "Disk size for the primary node pool"
  default     = 100
}

variable "primary_gpu_count" {
  type        = number
  description = "Number of GPUs to attach to the primary node pool, Set to 0 to not attach any GPU"
  default     = 0
}

variable "primary_gpu_type" {
  description = "Type of GPU to attach to the primary node pool"
  default     = "nvidia-tesla-t4"
}

variable "secondary_node_count" {
  type        = number
  description = "Number of nodes in the secondary node pool"
  default     = 0
}

variable "secondary_machine_type" {
  type        = string
  description = "Machine type for the secondary node pool"
  default     = "n1-highmem-2"
}

variable "secondary_disk_size_gb" {
  type        = number
  description = "Disk size for the secondary node pool"
  default     = 50
}

variable "secondary_gpu_count" {
  type        = number
  description = "Number of GPUs to attach to the secondary node pool, Set to 0 to not attach any GPU"
  default     = 0
}

variable "secondary_gpu_type" {
  description = "Type of GPU to attach to the secondary node pool"
  default     = "nvidia-tesla-t4"
}
