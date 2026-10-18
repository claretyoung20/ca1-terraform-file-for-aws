# Step 8 - Coupon service on a single EC2 in public subnet 1.
# The user data is a 2-line bootstrap: it fetches ca1-aws/aws/coupon-userdata.sh from S3
# and runs it, so fixing the real script only needs a re-upload (terraform apply).

resource "aws_instance" "coupon" {
  ami                         = nonsensitive(data.aws_ssm_parameter.al2023_x86.value)
  instance_type               = var.coupon_instance_type
  subnet_id                   = aws_subnet.public[0].id
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.coupon.id]
  iam_instance_profile        = aws_iam_instance_profile.ec2.name
  monitoring                  = true # detailed monitoring: Coupon CPU is evidence

  user_data = <<-EOT
    #!/bin/bash
    aws s3 cp s3://${aws_s3_bucket.artifacts.bucket}/ca1-aws/aws/coupon-userdata.sh /tmp/ud.sh --region ${var.region} && bash /tmp/ud.sh
  EOT

  credit_specification {
    cpu_credits = "unlimited"
  }

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required" # IMDSv2 only
  }

  root_block_device {
    volume_size = 8
    volume_type = "gp3"
  }

  lifecycle {
    ignore_changes = [ami]
  }

  # Everything the user data reads at first boot must exist before the instance starts.
  depends_on = [
    aws_s3_object.jar,
    aws_s3_object.ca1_aws,
    aws_ssm_parameter.db_host,
    aws_ssm_parameter.db_username,
    aws_ssm_parameter.db_password,
    aws_iam_role_policy.app_access,
    aws_iam_role_policy_attachment.ssm_core,
  ]

  # Exactly "ca1-coupon": create-dashboard.sh finds the instance by this tag.
  tags = { Name = "${var.name}-coupon" }
}

# Read by the Product service user data. Keep the trailing slash.
resource "aws_ssm_parameter" "coupon_url" {
  name  = "/${var.name}/coupon/url"
  type  = "String"
  tier  = "Standard"
  value = "http://${aws_instance.coupon.private_ip}:9091/couponapi/coupons/"
}
