variable "cluster_kubernetes_version" {
    type = string
    default     = "1.24.10"
    description = "Kubernetes version for the cluster"
}

variable "blue_active" {
    type = bool
    default     = true
    description = "Determines whether the blue environment will be created or destroyed"
}

variable "blue_state" {
    type = string
    default     = "live"
    description = "Should be one of live, target"
}

variable "blue_kubernetes_version" {
    type = string
    default     = "1.24.10"
    description = "Kubernetes version for the blue environment"
}

variable "green_active" {
    type = bool
    default     = false
    description = "Determines whether the green environment will be created or destroyed"
}

variable "green_state" {
    type = string
    default     = "target"
    description = "Should be one of live, target"
}

variable "green_kubernetes_version" {
    type = string
    default     = "1.24.10"
    description = "Kubernetes version for the green environment"
}