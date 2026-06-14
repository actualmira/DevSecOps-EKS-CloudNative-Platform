resource "aws_vpc" "devsecops" {
  cidr_block = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support = true
  
  tags = {
    Name = "devsecops-vpc"
    Env = "dev"
  }
}

data "aws_availability_zones" "devsecops" {
  state = "available"
}

locals {
  azs = data.aws_availability_zones.devsecops.names

  public_subnet_cidrs   = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  private_subnet_cidrs  = ["10.0.4.0/24", "10.0.5.0/24", "10.0.6.0/24"]
  isolated_subnet_cidrs = ["10.0.8.0/24", "10.0.9.0/24", "10.0.10.0/24"]
}
resource "aws_subnet" "public" {
  count = 3
  vpc_id = aws_vpc.devsecops.id
  cidr_block = local.public_subnet_cidrs[count.index]
  availability_zone  = local.azs[count.index]
  tags = {
    Name = "devsecops-public-${count.index + 1}"
    Env  = "dev"
  }
}

resource "aws_subnet" "private" {
  count = 3
  vpc_id = aws_vpc.devsecops.id
  cidr_block = local.private_subnet_cidrs[count.index]
  availability_zone  = local.azs[count.index]
  tags = {
    Name = "devsecops-private-${count.index + 1}"
    Env  = "dev"
  }
}

resource "aws_subnet" "isolated" {
  count = 3
  vpc_id = aws_vpc.devsecops.id
  cidr_block = local.isolated_subnet_cidrs[count.index]
  availability_zone  = local.azs[count.index]
  tags = {
    Name = "devsecops-isolated-${count.index + 1}"
    Env  = "dev"
  }
}

resource "aws_internet_gateway" "devsecops" {
  vpc_id = aws_vpc.devsecops.id
  tags = {
    Name = "devsecops-igw"
    Env  = "dev"
  }
}

resource "aws_eip" "nat" {
  domain = "vpc"  
  tags = {
    Name = "devsecops-eip"
    Env  = "dev"
  }
}

resource "aws_nat_gateway" "devsecops" {
  allocation_id = aws_eip.nat.id
  subnet_id = aws_subnet.public[0].id

  depends_on = [aws_internet_gateway.devsecops]

  tags = {
    Name = "devsecops-nat"
    Env  = "dev"
  }
}
