variable "environment" {
  type        = string
}

variable "project" {
  type        = string
}

variable "kubernetes_version" {
  type        = string
  default     = "1.35"
}

variable "vpc_id" {
  type        = string
}

variable "private_subnet_ids" {
  type        = list(string)
}

variable "isolated_subnet_ids" {
  type        = list(string)
}

variable "apps_security_group_id" {
  type        = string
}

variable "isolated_security_group_id" {
  type        = string
}

variable "sts_vpc_endpoint_id" {
  type        = string
}

variable "ssm_session_logging_policy_arn" {
  type        = string
}

variable "observability_security_group_id" {
  type        = string
}

variable "loki_s3_bucket_arn" {
  type        = string
}

variable "loki_kms_key_id" {
  type        = string
}

variable "alertmanager_sns_topic_arn" {
  type        = string
}
