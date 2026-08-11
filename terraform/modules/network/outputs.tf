output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.devsecops.id
}

output "private_subnet_ids" {
  description = "Private subnet IDs"
  value       = aws_subnet.private[*].id
}

output "isolated_subnet_ids" {
  description = "Isolated subnet IDs"
  value       = aws_subnet.isolated[*].id
}

output "apps_security_group_id" {
  description = "Application nodes security group ID"
  value       = aws_security_group.apps.id
}

output "isolated_security_group_id" {
  description = "Isolated nodes security group ID"
  value       = aws_security_group.isolated.id
}

output "sts_vpc_endpoint_id" {
  description = "ID of the STS VPC endpoint"
  value       = aws_vpc_endpoint.sts.id
}
