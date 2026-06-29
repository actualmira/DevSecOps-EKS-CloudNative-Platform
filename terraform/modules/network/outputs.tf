output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.devsecops.id
}

output "vpc_cidr" {
  description = "VPC CIDR block"
  value       = aws_vpc.devsecops.cidr_block
}

output "public_subnet_ids" {
  description = "Public subnet IDs"
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "Private subnet IDs"
  value       = aws_subnet.private[*].id
}

output "isolated_subnet_ids" {
  description = "Isolated subnet IDs"
  value       = aws_subnet.isolated[*].id
}

output "alb_security_group_id" {
  description = "ALB security group ID"
  value       = aws_security_group.alb.id
}

output "apps_security_group_id" {
  description = "Application nodes security group ID"
  value       = aws_security_group.apps.id
}

output "isolated_security_group_id" {
  description = "Isolated nodes security group ID"
  value       = aws_security_group.isolated.id
}

output "vpc_endpoints_security_group_id" {
  description = "VPC interface endpoints security group ID"
  value       = aws_security_group.vpc_endpoints.id
}

output "vpc_endpoints_kms_security_group_id" {
  description = "KMS VPC endpoint security group ID (isolated tier only)"
  value       = aws_security_group.vpc_endpoints_kms.id
}

output "sts_vpc_endpoint_id" {
  description = "ID of the STS VPC endpoint"
  value       = aws_vpc_endpoint.sts.id
}
