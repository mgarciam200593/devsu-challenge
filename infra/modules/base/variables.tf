variable "vpc_cidr" {
  type        = string
  description = "Cidr Block for VPC"
}

variable "az" {
  type        = list(string)
  description = "Availability Zones to deploy Subnets"
}

variable "public_cidr" {
  type        = list(string)
  description = "Cidr Blocks for Public Subnets"
}

variable "private_cidr" {
  type        = list(string)
  description = "Cidr Blocks for Private Subnets"
}

variable "cluster_name" {
  type        = string
  description = "Name for EKS Cluster"
}