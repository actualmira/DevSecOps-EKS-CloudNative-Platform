output "vpc_id" {
  value       = aws_vpc.devsecops.id
}

output "private_subnet_ids" {
  value       = aws_subnet.private[*].id
}

output "isolated_subnet_ids" {
  value       = aws_subnet.isolated[*].id
}

output "apps_security_group_id" {
  value       = aws_security_group.apps.id
}

output "isolated_security_group_id" {
  value       = aws_security_group.isolated.id
}

output "sts_vpc_endpoint_id" {
  value       = aws_vpc_endpoint.sts.id
}

output "observability_security_group_id" {
  value       = aws_security_group.observability_node.id
}
