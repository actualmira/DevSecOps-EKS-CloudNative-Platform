locals {
  environment = "dev"
  project     = "devsecops"
  aws_region  = "eu-west-1"
  vpc_cidr    = "10.0.0.0/16"
}

remote_state {
  backend = "s3"
  generate = {
    path      = "backend.tf"
    if_exists = "overwrite"
  }
  config = {
    bucket         = "devsecops-eks-05-26"
    key            = "environments/dev/${path_relative_to_include()}/terraform.tfstate"
    region         = "eu-west-1"
    dynamodb_table = "terraform-state-lock"
    encrypt        = true
    kms_key_id     = "alias/terraform-state-key"
  }
}
generate "main" {
  path      = "main.tf"
  if_exists = "overwrite"
  contents  = <<EOF
terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    http = {
      source  = "hashicorp/http"
      version = "~> 3.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.0"
    }
  }
}

provider "aws" {
  region = "${local.aws_region}"
}
provider "http" {}
provider "tls" {}
provider "archive" {}
EOF
}

inputs = {
  environment = local.environment
  project     = local.project
  aws_region  = local.aws_region
  vpc_cidr    = local.vpc_cidr
}
