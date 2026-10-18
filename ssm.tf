# Step 6 - Parameter Store. The services' user data and db/dbtool.py read these at runtime.

resource "aws_ssm_parameter" "db_username" {
  name  = "/${var.name}/db/username"
  type  = "String"
  tier  = "Standard"
  value = aws_db_instance.main.username
}

# SecureString with no key_id uses the AWS-managed key alias/aws/ssm.
resource "aws_ssm_parameter" "db_password" {
  name  = "/${var.name}/db/password"
  type  = "SecureString"
  tier  = "Standard"
  value = random_password.db.result
}

# Known as soon as RDS exists, so it is created here rather than by hand later.
# Hostname only - the user data appends :3306.
resource "aws_ssm_parameter" "db_host" {
  name  = "/${var.name}/db/host"
  type  = "String"
  tier  = "Standard"
  value = aws_db_instance.main.address
}
