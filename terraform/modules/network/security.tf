resource "aws_security_group" "alb" {
  name        = "${var.project}-${var.environment}-alb-sg"
  description = "Security group for Application Load Balancer"
  vpc_id      = aws_vpc.devsecops.id

  tags = {
    Name        = "${var.project}-${var.environment}-alb-sg"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_security_group" "apps" {
  name        = "${var.project}-${var.environment}-apps-sg"
  description = "Security group for application nodes running DVWA, ESO, Observability, Falco"
  vpc_id      = aws_vpc.devsecops.id

  tags = {
    Name        = "${var.project}-${var.environment}-apps-sg"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_security_group" "isolated" {
  name        = "${var.project}-${var.environment}-isolated-sg"
  description = "Security group for isolated nodes running MariaDB and Vault"
  vpc_id      = aws_vpc.devsecops.id

  tags = {
    Name        = "${var.project}-${var.environment}-isolated-sg"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_security_group" "vpc_endpoints" {
  name        = "${var.project}-${var.environment}-vpc-endpoints-sg"
  description = "Security group for VPC interface endpoints (ECR, STS, EKS, Logs)"
  vpc_id      = aws_vpc.devsecops.id

  tags = {
    Name        = "${var.project}-${var.environment}-vpc-endpoints-sg"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_security_group" "vpc_endpoints_kms" {
  name        = "${var.project}-${var.environment}-vpc-endpoints-kms-sg"
  description = "Security group for the KMS VPC endpoint for isolated tier only"
  vpc_id      = aws_vpc.devsecops.id

  tags = {
    Name        = "${var.project}-${var.environment}-vpc-endpoints-kms-sg"
    Environment = var.environment
    Project     = var.project
  }
}

# ALB rules
resource "aws_vpc_security_group_ingress_rule" "alb_https" {
  security_group_id = aws_security_group.alb.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"

  tags = {
    Name = "${var.project}-${var.environment}-alb-https-inbound"
  }
}

resource "aws_vpc_security_group_ingress_rule" "alb_http" {
  security_group_id = aws_security_group.alb.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 80
  to_port           = 80
  ip_protocol       = "tcp"

  tags = {
    Name = "${var.project}-${var.environment}-alb-http"
  }
}

# Application node rules
resource "aws_vpc_security_group_ingress_rule" "apps_from_alb" {
  security_group_id            = aws_security_group.apps.id
  referenced_security_group_id = aws_security_group.alb.id
  from_port                    = 80
  to_port                      = 80
  ip_protocol                  = "tcp"

  tags = {
    Name = "${var.project}-${var.environment}-apps-from-alb"
  }
}

resource "aws_vpc_security_group_egress_rule" "apps_to_mariadb" {
  security_group_id            = aws_security_group.apps.id
  referenced_security_group_id = aws_security_group.isolated.id
  from_port                    = 3306
  to_port                      = 3306
  ip_protocol                  = "tcp"

  tags = {
    Name = "${var.project}-${var.environment}-apps-to-mariadb"
  }
}

resource "aws_vpc_security_group_egress_rule" "eso_to_vault" {
  security_group_id            = aws_security_group.apps.id
  referenced_security_group_id = aws_security_group.isolated.id
  from_port                    = 8200
  to_port                      = 8200
  ip_protocol                  = "tcp"

  tags = {
    Name = "${var.project}-${var.environment}-eso-to-vault"
  }
}

resource "aws_vpc_security_group_egress_rule" "apps_to_internet" {
  security_group_id = aws_security_group.apps.id
  cidr_ipv4          = "0.0.0.0/0"
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"

  tags = {
    Name = "${var.project}-${var.environment}-apps-to-internet"
  }
}

# Isolated node rules
resource "aws_vpc_security_group_ingress_rule" "isolated_from_apps_mariadb" {
  security_group_id            = aws_security_group.isolated.id
  referenced_security_group_id = aws_security_group.apps.id
  from_port                    = 3306
  to_port                      = 3306
  ip_protocol                  = "tcp"

  tags = {
    Name = "${var.project}-${var.environment}-isolated-from-apps-mariadb"
  }
}

resource "aws_vpc_security_group_ingress_rule" "isolated_from_eso_vault" {
  security_group_id            = aws_security_group.isolated.id
  referenced_security_group_id = aws_security_group.apps.id
  from_port                    = 8200
  to_port                      = 8200
  ip_protocol                  = "tcp"

  tags = {
    Name = "${var.project}-${var.environment}-isolated-from-eso-vault"
  }
}

resource "aws_vpc_security_group_egress_rule" "isolated_to_vpc_endpoints" {
  security_group_id            = aws_security_group.isolated.id
  referenced_security_group_id = aws_security_group.vpc_endpoints.id
  from_port                    = 443
  to_port                      = 443
  ip_protocol                  = "tcp"

  tags = {
    Name = "${var.project}-${var.environment}-isolated-to-vpc-endpoints"
  }
}

resource "aws_vpc_security_group_egress_rule" "isolated_to_vpc_endpoints_kms" {
  security_group_id            = aws_security_group.isolated.id
  referenced_security_group_id = aws_security_group.vpc_endpoints_kms.id
  from_port                    = 443
  to_port                      = 443
  ip_protocol                  = "tcp"

  tags = {
    Name = "${var.project}-${var.environment}-isolated-to-vpc-endpoints-kms"
  }
}

resource "aws_vpc_security_group_egress_rule" "isolated_to_internet" {
  security_group_id = aws_security_group.isolated.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"

  tags = {
    Name = "${var.project}-${var.environment}-isolated-to-internet"
  }
}

# VPC Endpoints SG rules
resource "aws_vpc_security_group_ingress_rule" "endpoints_from_apps" {
  security_group_id            = aws_security_group.vpc_endpoints.id
  referenced_security_group_id = aws_security_group.apps.id
  from_port                    = 443
  to_port                      = 443
  ip_protocol                  = "tcp"

  tags = {
    Name = "${var.project}-${var.environment}-endpoints-from-apps"
  }
}

resource "aws_vpc_security_group_ingress_rule" "endpoints_from_isolated" {
  security_group_id            = aws_security_group.vpc_endpoints.id
  referenced_security_group_id = aws_security_group.isolated.id
  from_port                    = 443
  to_port                      = 443
  ip_protocol                  = "tcp"

  tags = {
    Name = "${var.project}-${var.environment}-endpoints-from-isolated"
  }
}

# KMS Endpoint SG rules for isolated tier 
resource "aws_vpc_security_group_ingress_rule" "kms_endpoint_from_isolated" {
  security_group_id            = aws_security_group.vpc_endpoints_kms.id
  referenced_security_group_id = aws_security_group.isolated.id
  from_port                    = 443
  to_port                      = 443
  ip_protocol                  = "tcp"

  tags = {
    Name = "${var.project}-${var.environment}-kms-endpoint-from-isolated"
  }
}
