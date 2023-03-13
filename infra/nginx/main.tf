terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "> 4.45.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "> 2.16.1"
    }
  }
  backend "s3" {
    bucket               = "devsu-challenge"
    workspace_key_prefix = "environments"
    key                  = "nginx"
    region               = "us-east-1"
  }
}

data "terraform_remote_state" "remote" {
  backend = "s3"

  config = {
    bucket               = "devsu-challenge"
    workspace_key_prefix = "environments"
    key                  = "base"
    region               = "us-east-1"
  }
}

data "aws_eks_cluster" "cluster" {
  name = data.terraform_remote_state.remote.outputs.cluster_name
}

provider "aws" {
  region = "us-east-1"
  default_tags {
    tags = {
      Name        = "devsu"
      Environment = terraform.workspace
    }
  }
}

provider "kubernetes" {
  host                   = data.aws_eks_cluster.cluster.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.cluster.certificate_authority.0.data)
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args = [
      "eks",
      "get-token",
      "--region",
      "us-east-1",
      "--cluster-name",
      data.aws_eks_cluster.cluster.name
    ]
  }
}

module "nginx" {
  source          = "../modules/nginx"
  cluster_name    = data.terraform_remote_state.remote.outputs.cluster_name
  node_group_name = terraform.workspace
  nginx_ns        = "nginx-ingress-${terraform.workspace}"
  env             = terraform.workspace
}