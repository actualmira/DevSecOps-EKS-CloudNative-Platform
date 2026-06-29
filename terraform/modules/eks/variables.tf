variable "environment" {
  description = "Environment name"
  type        = string
}

variable "project" {
  description = "Project name"
  type        = string
}

variable "kubernetes_version" {
  description = "EKS Kubernetes version"
  type        = string
  default     = "1.35"
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnet IDs"
  type        = list(string)
}

variable "isolated_subnet_ids" {
  description = "Isolated subnet IDs"
  type        = list(string)
}

variable "apps_security_group_id" {
  description = "App nodes security group ID"
  type        = string
}

variable "isolated_security_group_id" {
  description = "Isolated nodes security group ID"
  type        = string
}

variable "eks_secrets_key_arn" {
  description = "KMS key ARN for EKS etcd secrets encryption"
  type        = string
}

variable "vault_unseal_key_arn" {
  description = "KMS key ARN for Vault auto-unseal"
  type        = string
}

variable "sts_vpc_endpoint_id" {
  description = "STS VPC endpoint ID"
  type        = string
}

variable "ssm_session_logging_policy_arn" {
  description = "IAM policy ARN for SSM session logging"
  type        = string
}
