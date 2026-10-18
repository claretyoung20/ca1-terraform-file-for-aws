# Step 7 - Load-generator EC2 in public subnet 1. No key pair or inbound rules:
# connect with Session Manager, then run the commands in the "loadgen_setup_commands" output.

data "aws_ssm_parameter" "al2023_x86" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

resource "aws_instance" "loadgen" {
  ami                         = nonsensitive(data.aws_ssm_parameter.al2023_x86.value)
  instance_type               = var.loadgen_instance_type
  subnet_id                   = aws_subnet.public[0].id
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.loadgen.id]
  iam_instance_profile        = aws_iam_instance_profile.ec2.name
  monitoring                  = false # no detailed CloudWatch monitoring

  # CPU-credit settings only exist for burstable (t*) types; skip the block for c6a etc.
  dynamic "credit_specification" {
    for_each = startswith(var.loadgen_instance_type, "t") ? [1] : []
    content {
      cpu_credits = "unlimited"
    }
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
    # A newer AL2023 AMI shouldn't replace the instance (and wipe ~/results).
    ignore_changes = [ami]
  }

  tags = { Name = "${var.name}-loadgen" }
}
