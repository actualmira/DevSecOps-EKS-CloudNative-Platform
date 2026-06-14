resource "aws_route_table" "public" {
  vpc_id = aws_vpc.devsecops.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.devsecops.id
  }

  tags = {
    Name = "devsecops-public-rt"
    Env  = "dev"
  }
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.devsecops.id
  route {
    cidr_block     = "0.0.0.0/0"
   nat_gateway_id = aws_nat_gateway.devsecops.id
  }

  tags = {
    Name = "devsecops-private-rt"
    Env  = "dev"
  }
}

resource "aws_route_table" "isolated" {
  vpc_id = aws_vpc.devsecops.id

  tags = {
    Name = "devsecops-isolated-rt"
    Env  = "dev"
  }
}

resource "aws_route_table_association" "public" {
  count          = 3
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private" {
  count          = 3
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "isolated" {
  count = 3
  subnet_id = aws_subnet.isolated[count.index].id
  route_table_id = aws_route_table.isolated.id
}
