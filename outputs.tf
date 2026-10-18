output "vpc_id" {
  value = aws_vpc.main.id
}

output "public_subnet_ids" {
  value = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  value = aws_subnet.private[*].id
}

output "security_group_ids" {
  value = {
    alb     = aws_security_group.alb.id
    product = aws_security_group.product.id
    coupon  = aws_security_group.coupon.id
    rds     = aws_security_group.rds.id
    loadgen = aws_security_group.loadgen.id
  }
}

output "bucket_name" {
  value = aws_s3_bucket.artifacts.bucket
}

output "instance_profile_name" {
  value = aws_iam_instance_profile.ec2.name
}

output "ec2_role_arn" {
  value = aws_iam_role.ec2.arn
}

output "db_endpoint" {
  value = aws_db_instance.main.address
}

output "db_engine_version" {
  value = aws_db_instance.main.engine_version_actual
}

output "db_password" {
  value     = random_password.db.result
  sensitive = true
}

output "loadgen_instance_id" {
  value = aws_instance.loadgen.id
}

output "loadgen_setup_commands" {
  description = "Run in a Session Manager shell on ca1-loadgen."
  value       = <<-EOT
    export AWS_DEFAULT_REGION=${var.region} && echo 'export AWS_DEFAULT_REGION=${var.region}' >> ~/.bashrc
    aws s3 sync s3://${aws_s3_bucket.artifacts.bucket}/ca1-aws ~/ca1-aws --exclude "*__pycache__*"
    chmod +x ~/ca1-aws/*/*.sh
    bash ~/ca1-aws/aws/loadgen-setup.sh
  EOT
}

output "coupon_instance_id" {
  value = aws_instance.coupon.id
}

output "coupon_private_ip" {
  value = aws_instance.coupon.private_ip
}

output "coupon_test_command" {
  description = "Run from the load generator once the tables exist (dbtool.py init)."
  value       = "curl http://${aws_instance.coupon.private_ip}:9091/couponapi/coupons/SAVE10"
}

output "alb_dns_name" {
  value = aws_lb.main.dns_name
}

output "product_test_command" {
  description = "Smoke test through the ALB once the target is healthy."
  value       = "curl http://${aws_lb.main.dns_name}/productapi/products"
}

output "loadgen_env_commands" {
  description = "Run on the load generator before k6/run.sh."
  value       = "export BASE_URL=http://${aws_lb.main.dns_name} BUCKET=${aws_s3_bucket.artifacts.bucket}"
}

output "dashboard_url" {
  value = "https://${var.region}.console.aws.amazon.com/cloudwatch/home?region=${var.region}#dashboards/dashboard/${aws_cloudwatch_dashboard.main.dashboard_name}"
}

output "product_asg_config" {
  description = "Current experiment configuration (quote this in the experiment log)."
  value       = "min=${var.product_asg_min} desired=${var.enable_scaling ? "policy" : var.product_asg_desired} max=${var.product_asg_max} scaling=${var.enable_scaling} cpu_target=${var.cpu_target} warmup=${var.instance_warmup}s"
}
