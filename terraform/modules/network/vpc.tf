resource "aws_vpc" "devsecops" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags = {
    Name        = "${var.project}-${var.environment}-vpc"
    Environment = var.environment
    Project     = var.project
  }
}

data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  azs = slice(data.aws_availability_zones.available.names, 0, 3)

  public_subnet_cidrs   = [for i in range(3) : cidrsubnet(var.vpc_cidr, 8, i + 1)]
  private_subnet_cidrs  = [for i in range(3) : cidrsubnet(var.vpc_cidr, 8, i + 10)]
  isolated_subnet_cidrs = [for i in range(3) : cidrsubnet(var.vpc_cidr, 8, i + 20)]
}

resource "aws_subnet" "public" {
  count             = 3
  vpc_id            = aws_vpc.devsecops.id
  cidr_block        = local.public_subnet_cidrs[count.index]
  availability_zone = local.azs[count.index]
  tags = {
    Name                     = "${var.project}-${var.environment}-public-${count.index + 1}"
    Environment              = var.environment
    Project                  = var.project
    "kubernetes.io/role/elb" = "1"
  }
}

resource "aws_subnet" "private" {
  count             = 3
  vpc_id            = aws_vpc.devsecops.id
  cidr_block        = local.private_subnet_cidrs[count.index]
  availability_zone = local.azs[count.index]
  tags = {
    Name        = "${var.project}-${var.environment}-private-${count.index + 1}"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_subnet" "isolated" {
  count             = 3
  vpc_id            = aws_vpc.devsecops.id
  cidr_block        = local.isolated_subnet_cidrs[count.index]
  availability_zone = local.azs[count.index]
  tags = {
    Name        = "${var.project}-${var.environment}-isolated-${count.index + 1}"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_internet_gateway" "devsecops" {
  vpc_id = aws_vpc.devsecops.id
  tags = {
    Name        = "${var.project}-${var.environment}-igw"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_eip" "nat" {
  domain     = "vpc"
  depends_on = [aws_internet_gateway.devsecops]
  tags = {
    Name        = "${var.project}-${var.environment}-nat-eip"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_nat_gateway" "devsecops" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id
  depends_on    = [aws_internet_gateway.devsecops]
  tags = {
    Name        = "${var.project}-${var.environment}-nat"
    Environment = var.environment
    Project     = var.project
  }
}
