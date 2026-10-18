# Step 2 - Security groups chaining the tiers:
# internet -> ALB :80 -> product :9090 -> coupon :9091 -> RDS :3306
# The load generator may call coupon and RDS directly.

resource "aws_security_group" "alb" {
  name        = "${var.name}-alb-sg"
  description = "ALB - HTTP from the internet"
  vpc_id      = aws_vpc.main.id
  tags        = { Name = "${var.name}-alb-sg" }
}

resource "aws_security_group" "product" {
  name        = "${var.name}-product-sg"
  description = "Product service - 9090 from the ALB"
  vpc_id      = aws_vpc.main.id
  tags        = { Name = "${var.name}-product-sg" }
}

resource "aws_security_group" "coupon" {
  name        = "${var.name}-coupon-sg"
  description = "Coupon service - 9091 from product and loadgen"
  vpc_id      = aws_vpc.main.id
  tags        = { Name = "${var.name}-coupon-sg" }
}

resource "aws_security_group" "rds" {
  name        = "${var.name}-rds-sg"
  description = "RDS MySQL - 3306 from product, coupon and loadgen"
  vpc_id      = aws_vpc.main.id
  tags        = { Name = "${var.name}-rds-sg" }
}

resource "aws_security_group" "loadgen" {
  name        = "${var.name}-loadgen-sg"
  description = "Load generator - no inbound (use Session Manager)"
  vpc_id      = aws_vpc.main.id
  tags        = { Name = "${var.name}-loadgen-sg" }
}

# --- Inbound rules ---

resource "aws_vpc_security_group_ingress_rule" "alb_http" {
  security_group_id = aws_security_group.alb.id
  description       = "HTTP from anywhere"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_ingress_rule" "product_from_alb" {
  security_group_id            = aws_security_group.product.id
  description                  = "Product service from ALB"
  ip_protocol                  = "tcp"
  from_port                    = 9090
  to_port                      = 9090
  referenced_security_group_id = aws_security_group.alb.id
}

resource "aws_vpc_security_group_ingress_rule" "coupon" {
  for_each = {
    product = aws_security_group.product.id
    loadgen = aws_security_group.loadgen.id
  }

  security_group_id            = aws_security_group.coupon.id
  description                  = "Coupon service from ${each.key}"
  ip_protocol                  = "tcp"
  from_port                    = 9091
  to_port                      = 9091
  referenced_security_group_id = each.value
}

resource "aws_vpc_security_group_ingress_rule" "rds" {
  for_each = {
    product = aws_security_group.product.id
    coupon  = aws_security_group.coupon.id
    loadgen = aws_security_group.loadgen.id
  }

  security_group_id            = aws_security_group.rds.id
  description                  = "MySQL from ${each.key}"
  ip_protocol                  = "tcp"
  from_port                    = 3306
  to_port                      = 3306
  referenced_security_group_id = each.value
}

# --- Outbound: all traffic, like the console default ---
# (Terraform strips the default egress rule, so it is re-added explicitly.)

resource "aws_vpc_security_group_egress_rule" "all" {
  for_each = {
    alb     = aws_security_group.alb.id
    product = aws_security_group.product.id
    coupon  = aws_security_group.coupon.id
    rds     = aws_security_group.rds.id
    loadgen = aws_security_group.loadgen.id
  }

  security_group_id = each.value
  description       = "All outbound"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}
