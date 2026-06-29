terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  backend "s3" {
    bucket         = "devsecops-eks-05-26"
    key            = "environments/dev/terraform.tfstate"
    region         = "eu-west-1"
    dynamodb_table = "terraform-state-lock"
    encrypt        = true
    kms_key_id     = "alias/terraform-state-key"
  }
}

provider "aws" {
  region = var.aws_region
}

module "network" {
  source = "../../modules/network"

  environment = var.environment
  project     = var.project
  aws_region  = var.aws_region
  vpc_cidr    = var.vpc_cidr
}

module "security" {
  source = "../../modules/security"

  environment = var.environment
  project     = var.project
  aws_region  = var.aws_region
  vpc_id      = module.network.vpc_id
}

module "eks" {
  source = "../../modules/eks"

  environment = var.environment
  project     = var.project
  kubernetes_version = var.kubernetes_version

  vpc_id                     = module.network.vpc_id
  private_subnet_ids         = module.network.private_subnet_ids
  isolated_subnet_ids        = module.network.isolated_subnet_ids
  apps_security_group_id     = module.network.apps_security_group_id
  isolated_security_group_id = module.network.isolated_security_group_id
  sts_vpc_endpoint_id         = module.network.sts_vpc_endpoint_id

  eks_secrets_key_arn             = module.security.eks_secrets_kms_key_arn
  vault_unseal_key_arn            = module.security.vault_unseal_kms_key_arn
  ssm_session_logging_policy_arn  = module.security.ssm_session_logging_policy_arn
}
