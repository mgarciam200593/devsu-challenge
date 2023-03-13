terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "> 4.45.0"
    }
  }
  backend "s3" {
    bucket               = "devsu-challenge"
    workspace_key_prefix = "environments"
    key                  = "base"
    region               = "us-east-1"
  }
}

provider "aws" {
  region = "us-east-1"
  default_tags {
    tags = {
      Name = "devsu"
    }
  }
}

module "base" {
  source       = "../modules/base"
  vpc_cidr     = var.vpc_cidr
  public_cidr  = var.public_cidr
  private_cidr = var.private_cidr
  az           = var.az
  cluster_name = var.cluster_name
}