variable "cluster_name" {
  type        = string
  description = "Name for EKS Cluster"
}

variable "node_group_name" {
  type        = string
  description = "Name for EKS Node Group"
}

variable "nginx_ns" {
  type        = string
  description = "Name for Nginx Namespace"
}

variable "env" {
  type        = string
  description = "Name of environment"
}
