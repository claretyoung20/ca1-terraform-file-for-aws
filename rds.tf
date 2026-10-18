# Step 5a - DB subnet group: the database lives in the two private subnets only.
resource "aws_db_subnet_group" "main" {
  name        = "${var.name}-db-subnets"
  description = "${var.name} private subnets for RDS"
  subnet_ids  = aws_subnet.private[*].id
}

# Step 5b - MySQL 8.4 on RDS, single-AZ, cheapest settings.

# Letters and digits only, as the playbook asks. Stored in SSM (Step 6);
# read it back with:  terraform output -raw db_password
resource "random_password" "db" {
  length  = 20
  special = false
}

data "aws_rds_engine_version" "mysql" {
  engine  = "mysql"
  version = "8.4"
  latest  = true
}

resource "aws_db_instance" "main" {
  identifier     = "${var.name}-db"
  engine         = "mysql"
  engine_version = data.aws_rds_engine_version.mysql.version
  instance_class = var.db_instance_class

  db_name  = "servicedb"
  username = "admin"
  password = random_password.db.result

  allocated_storage     = 20
  max_allocated_storage = 0 # storage autoscaling off
  storage_type          = "gp3"
  storage_encrypted     = true

  multi_az               = false
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  publicly_accessible    = false

  monitoring_interval = 0 # Enhanced Monitoring off

  backup_retention_period = 1
  deletion_protection     = false
  skip_final_snapshot     = true
  apply_immediately       = true

  lifecycle {
    # RDS applies minor upgrades itself; don't fight it when a newer 8.4.x appears.
    ignore_changes = [engine_version]
  }

  tags = { Name = "${var.name}-db" }
}
