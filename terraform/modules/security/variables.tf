variable "environment" {
  type        = string
}

variable "project" {
  type        = string
}

variable "aws_region" {
  type        = string
  default     = "eu-west-1"
}

variable "vpc_id" {
  type        = string
}
variable "lambda_source_path" {
  type        = string
}
