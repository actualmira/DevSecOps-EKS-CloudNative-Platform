resource "aws_security_group" "alb" {
  name        = "devsecops-alb-sg"
  description = "Security group for ALB"
  vpc_id      = aws_vpc.devsecops.id
  tags = {
    Name = "devsecops-alb-sg"
    Env  = "dev"
  }
}

resource "aws_security_group" "apps" {
  name        = "devsecops-apps-sg"
  description = "Security group for applications node"
  vpc_id      = aws_vpc.devsecops.id
  tags = {
    Name = "devsecops-apps-sg"
    Env  = "dev"
  }
}

resource "aws_security_group" "isolated" {
  name        = "devsecops-isolated-sg"
  description = "Security group for the isolated node"
  vpc_id      = aws_vpc.devsecops.id
  tags = {
    Name = "devsecops-isolated-sg"
    Env  = "dev"
  }
}

resource "aws_vpc_security_group_ingress_rule" "alb_https" {
  security_group_id = aws_security_group.alb.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
  tags = {
    Name = "alb-https-inbound"
  }
}

resource "aws_vpc_security_group_egress_rule" "apps_outbound" {
  security_group_id = aws_security_group.apps.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
  tags = {
    Name = "apps-outbound"
  }
}

resource "aws_vpc_security_group_egress_rule" "apps_to_db" {
  security_group_id            = aws_security_group.apps.id
  referenced_security_group_id = aws_security_group.isolated.id
  from_port                    = 3306
  to_port                      = 3306
  ip_protocol                  = "tcp"
  tags = {
    Name = "apps-to-db-outbound"
  }
}

resource "aws_vpc_security_group_egress_rule" "eso_to_vault" {
  security_group_id            = aws_security_group.apps.id
  referenced_security_group_id = aws_security_group.isolated.id
  from_port                    = 8200
  to_port                      = 8200
  ip_protocol                  = "tcp"
  tags = {
    Name = "eso_to_vault-outbound"
  }
}

resource "aws_vpc_security_group_ingress_rule" "isolated_from_apps" {
  security_group_id            = aws_security_group.isolated.id
  referenced_security_group_id = aws_security_group.apps.id
  from_port                    = 3306
  to_port                      = 3306
  ip_protocol                  = "tcp"
  tags = {
    Name = "isolated-from-apps-inbound"
  }
}

resource "aws_vpc_security_group_ingress_rule" "isolated_vault_from_eso" {
  security_group_id            = aws_security_group.isolated.id
  referenced_security_group_id = aws_security_group.apps.id
  from_port                    = 8200
  to_port                      = 8200
  ip_protocol                  = "tcp"
  tags = {
    Name = "isolated-vault-from-eso-inbound"
  }
}

resource "aws_vpc_security_group_egress_rule" "isolated_to_vpc_endpoints" {
  security_group_id = aws_security_group.isolated.id
  cidr_ipv4         = "10.0.4.0/22"
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
  tags = {
    Name = "isolated-to-vpc-endpoints-outbound"
  }
}
resource "aws_network_acl" "isolated" {
  vpc_id     = aws_vpc.devsecops.id
  subnet_ids = aws_subnet.isolated[*].id

  ingress {
    rule_no    = 100
    protocol   = "-1"
    action     = "allow"
    cidr_block = "10.0.4.0/22"
    from_port  = 0
    to_port    = 0
  }

  egress {
    rule_no    = 100
    protocol   = "-1"
    action     = "allow"
    cidr_block = "10.0.4.0/22"
    from_port  = 0
    to_port    = 0
  }

  tags = {
    Name = "devsecops-isolated-nacl"
    Env  = "dev"
  }
}
