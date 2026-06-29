resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.devsecops.id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"

  route_table_ids = [
    aws_route_table.private.id,
    aws_route_table.isolated.id
  ]

  tags = {
    Name        = "${var.project}-${var.environment}-s3-endpoint"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_vpc_endpoint" "ecr_api" {
  vpc_id              = aws_vpc.devsecops.id
  service_name        = "com.amazonaws.${var.aws_region}.ecr.api"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  subnet_ids          = [aws_subnet.private[0].id]
  security_group_ids  = [aws_security_group.vpc_endpoints.id]

  tags = {
    Name        = "${var.project}-${var.environment}-ecr-api-endpoint"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_vpc_endpoint" "ecr_dkr" {
  vpc_id              = aws_vpc.devsecops.id
  service_name        = "com.amazonaws.${var.aws_region}.ecr.dkr"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  subnet_ids          = [aws_subnet.private[0].id]
  security_group_ids  = [aws_security_group.vpc_endpoints.id]

  tags = {
    Name        = "${var.project}-${var.environment}-ecr-dkr-endpoint"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_vpc_endpoint" "kms" {
  vpc_id              = aws_vpc.devsecops.id
  service_name        = "com.amazonaws.${var.aws_region}.kms"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  subnet_ids          = [aws_subnet.private[0].id]
  security_group_ids  = [aws_security_group.vpc_endpoints_kms.id]

  tags = {
    Name        = "${var.project}-${var.environment}-kms-endpoint"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_vpc_endpoint" "sts" {
  vpc_id              = aws_vpc.devsecops.id
  service_name        = "com.amazonaws.${var.aws_region}.sts"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  subnet_ids          = [aws_subnet.private[0].id]
  security_group_ids  = [aws_security_group.vpc_endpoints.id]

  tags = {
    Name        = "${var.project}-${var.environment}-sts-endpoint"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_vpc_endpoint" "ec2" {
  vpc_id              = aws_vpc.devsecops.id
  service_name        = "com.amazonaws.${var.aws_region}.ec2"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  subnet_ids          = [aws_subnet.private[0].id]
  security_group_ids  = [aws_security_group.vpc_endpoints.id]

  tags = {
    Name        = "${var.project}-${var.environment}-ec2-endpoint"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_vpc_endpoint" "ssm" {
  vpc_id              = aws_vpc.devsecops.id
  service_name        = "com.amazonaws.${var.aws_region}.ssm"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  subnet_ids          = [aws_subnet.private[0].id]
  security_group_ids  = [aws_security_group.vpc_endpoints.id]

  tags = {
    Name        = "${var.project}-${var.environment}-ssm-endpoint"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_vpc_endpoint" "ssmmessages" {
  vpc_id              = aws_vpc.devsecops.id
  service_name        = "com.amazonaws.${var.aws_region}.ssmmessages"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  subnet_ids          = [aws_subnet.private[0].id]
  security_group_ids  = [aws_security_group.vpc_endpoints.id]

  tags = {
    Name        = "${var.project}-${var.environment}-ssmmessages-endpoint"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_vpc_endpoint" "ec2messages" {
  vpc_id              = aws_vpc.devsecops.id
  service_name        = "com.amazonaws.${var.aws_region}.ec2messages"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  subnet_ids          = [aws_subnet.private[0].id]
  security_group_ids  = [aws_security_group.vpc_endpoints.id]

  tags = {
    Name        = "${var.project}-${var.environment}-ec2messages-endpoint"
    Environment = var.environment
    Project     = var.project
  }
}
