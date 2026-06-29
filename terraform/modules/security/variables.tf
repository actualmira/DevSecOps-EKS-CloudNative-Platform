variable "environment" {
  description = "Environment name used for tagging"
  type        = string
}

variable "project" {
  description = "Project name used for resource naming and tagging"
  type        = string
}

variable "aws_region" {
  description = "AWS region for resource deployment"
  type        = string
  default     = "eu-west-1"
}

variable "vpc_id" {
  description = "VPC ID to attach the flow log"
  type        = string
}
