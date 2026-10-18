# Step 1 - VPC across two AZs: 2 public + 2 private subnets, no NAT gateway,
# free S3 gateway endpoint. Mirrors the console's "VPC and more" wizard.

locals {
  azs = slice(data.aws_availability_zones.available.names, 0, 2)

  # Same /20 layout the console wizard generates for a /16
  public_cidrs  = [cidrsubnet(var.vpc_cidr, 4, 0), cidrsubnet(var.vpc_cidr, 4, 1)] # 10.0.0.0/20, 10.0.16.0/20
  private_cidrs = [cidrsubnet(var.vpc_cidr, 4, 8), cidrsubnet(var.vpc_cidr, 4, 9)] # 10.0.128.0/20, 10.0.144.0/20
}

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "${var.name}-vpc" }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${var.name}-igw" }
}

# Public subnets auto-assign a public IP: with no NAT gateway, instances need one
# to download Java and reach AWS APIs.
resource "aws_subnet" "public" {
  count = 2

  vpc_id                  = aws_vpc.main.id
  cidr_block              = local.public_cidrs[count.index]
  availability_zone       = local.azs[count.index]
  map_public_ip_on_launch = true

  tags = { Name = "${var.name}-subnet-public${count.index + 1}-${local.azs[count.index]}" }
}

resource "aws_subnet" "private" {
  count = 2

  vpc_id            = aws_vpc.main.id
  cidr_block        = local.private_cidrs[count.index]
  availability_zone = local.azs[count.index]

  tags = { Name = "${var.name}-subnet-private${count.index + 1}-${local.azs[count.index]}" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = { Name = "${var.name}-rtb-public" }
}

resource "aws_route_table_association" "public" {
  count = 2

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# Private route tables have only the local route (+ S3 endpoint): no internet access.
resource "aws_route_table" "private" {
  count = 2

  vpc_id = aws_vpc.main.id
  tags   = { Name = "${var.name}-rtb-private${count.index + 1}-${local.azs[count.index]}" }
}

resource "aws_route_table_association" "private" {
  count = 2

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}

# S3 gateway endpoint (free). Attached to the public route table too, so JAR
# downloads from the public-subnet instances stay on the AWS network.
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${var.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = concat([aws_route_table.public.id], aws_route_table.private[*].id)

  tags = { Name = "${var.name}-vpce-s3" }
}
