resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.devsecops.id
  service_name      = "com.amazonaws.eu-west-1.s3"
  vpc_endpoint_type = "Gateway"

  route_table_ids = [
    aws_route_table.private.id,
    aws_route_table.isolated.id
  ]

  tags = {
    Name = "devsecops-s3-endpoint"
    Env  = "dev"
  }
}

resource "aws_security_group" "vpc_endpoints" {
  name        = "devsecops-vpc-endpoints-sg"
  description = "Security group for VPC interface endpoints"
  vpc_id      = aws_vpc.devsecops.id

  tags = {
    Name = "devsecops-vpc-endpoints-sg"
    Env  = "dev"
  }
}

resource "aws_vpc_security_group_ingress_rule" "endpoints_from_private" {
  security_group_id = aws_security_group.vpc_endpoints.id
  cidr_ipv4         = "10.0.4.0/22"
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
  tags = {
    Name = "endpoints-from-private-subnets"
  }
}

resource "aws_vpc_security_group_ingress_rule" "endpoints_from_isolated" {
  security_group_id = aws_security_group.vpc_endpoints.id
  cidr_ipv4         = "10.0.8.0/22"
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
  tags = {
    Name = "endpoints-from-isolated-subnets"
  }
}

resource "aws_vpc_endpoint" "ecr_api" {
  vpc_id              = aws_vpc.devsecops.id
  service_name        = "com.amazonaws.eu-west-1.ecr.api"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  subnet_ids          = [aws_subnet.private[0].id]
  security_group_ids  = [aws_security_group.vpc_endpoints.id]

  tags = {
    Name = "devsecops-ecr-api-endpoint"
    Env  = "dev"
  }
}

resource "aws_vpc_endpoint" "ecr_dkr" {
  vpc_id              = aws_vpc.devsecops.id
  service_name        = "com.amazonaws.eu-west-1.ecr.dkr"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  subnet_ids          = [aws_subnet.private[0].id]
  security_group_ids  = [aws_security_group.vpc_endpoints.id]

  tags = {
    Name = "devsecops-ecr-dkr-endpoint"
    Env  = "dev"
  }
}

resource "aws_vpc_endpoint" "kms" {
  vpc_id              = aws_vpc.devsecops.id
  service_name        = "com.amazonaws.eu-west-1.kms"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  subnet_ids          = [aws_subnet.private[0].id]
  security_group_ids  = [aws_security_group.vpc_endpoints.id]

  tags = {
    Name = "devsecops-kms-endpoint"
    Env  = "dev"
  }
}

resource "aws_vpc_endpoint" "sts" {
  vpc_id              = aws_vpc.devsecops.id
  service_name        = "com.amazonaws.eu-west-1.sts"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  subnet_ids          = [aws_subnet.private[0].id]
  security_group_ids  = [aws_security_group.vpc_endpoints.id]

  tags = {
    Name = "devsecops-sts-endpoint"
    Env  = "dev"
  }
}
