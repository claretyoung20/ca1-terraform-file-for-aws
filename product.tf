# Steps 9-12 - Product service: launch template -> target group -> ALB -> Auto Scaling group.

# Step 9 - Launch template: the repeatable recipe for every Product server.
# No subnet or key pair; the ASG chooses the subnet and servers are reached via Session Manager.
resource "aws_launch_template" "product" {
  name                   = "${var.name}-product-lt"
  description            = "v1 baseline" # version description
  update_default_version = true

  image_id               = nonsensitive(data.aws_ssm_parameter.al2023_x86.value)
  instance_type          = var.product_instance_type
  vpc_security_group_ids = [aws_security_group.product.id]

  iam_instance_profile {
    name = aws_iam_instance_profile.ec2.name
  }

  monitoring {
    enabled = true # detailed CloudWatch monitoring
  }

  credit_specification {
    cpu_credits = "unlimited"
  }

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required" # IMDSv2 only
  }

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size = 8
      volume_type = "gp3"
    }
  }

  # 2-line bootstrap: fetch and run the real script from S3.
  user_data = base64encode(<<-EOT
    #!/bin/bash
    aws s3 cp s3://${aws_s3_bucket.artifacts.bucket}/ca1-aws/aws/product-userdata.sh /tmp/ud.sh --region ${var.region} && bash /tmp/ud.sh
  EOT
  )

  tag_specifications {
    resource_type = "instance"
    tags          = { Name = "${var.name}-product" }
  }

  lifecycle {
    # Keep every server in an experiment on the same AMI.
    ignore_changes = [image_id]
  }
}

# Step 10 - Target group: the healthy Product servers the ALB can use.
resource "aws_lb_target_group" "product" {
  name             = "${var.name}-product-tg"
  target_type      = "instance"
  protocol         = "HTTP"
  protocol_version = "HTTP1"
  port             = 9090
  vpc_id           = aws_vpc.main.id

  deregistration_delay = 30

  health_check {
    path                = "/actuator/health/liveness"
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 5
    interval            = 10
    matcher             = "200"
  }
}

# Step 11 - Internet-facing ALB in both public subnets.
resource "aws_lb" "main" {
  name               = "${var.name}-alb"
  load_balancer_type = "application"
  internal           = false
  ip_address_type    = "ipv4"
  security_groups    = [aws_security_group.alb.id]
  subnets            = aws_subnet.public[*].id
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.product.arn
  }
}

# Step 12 - Auto Scaling group. Baseline: exactly one server, no scaling policies.
resource "aws_autoscaling_group" "product" {
  name                = "${var.name}-product-asg"
  vpc_zone_identifier = aws_subnet.public[*].id
  target_group_arns   = [aws_lb_target_group.product.arn]

  launch_template {
    id      = aws_launch_template.product.id
    version = "$Latest"
  }

  min_size         = var.product_asg_min
  max_size         = var.product_asg_max
  # Fixed-size experiments (A, C, E): Terraform sets desired capacity.
  # Scaling experiment (D): null = leave desired capacity to the scaling policy.
  desired_capacity = var.enable_scaling ? null : var.product_asg_desired

  default_instance_warmup = var.instance_warmup

  health_check_type         = "ELB"
  health_check_grace_period = 180

  # "Enable group metrics collection within CloudWatch" (all group metrics, 1-minute)
  metrics_granularity = "1Minute"
  enabled_metrics = [
    "GroupMinSize", "GroupMaxSize", "GroupDesiredCapacity",
    "GroupInServiceInstances", "GroupPendingInstances", "GroupStandbyInstances",
    "GroupTerminatingInstances", "GroupTotalInstances",
    "GroupInServiceCapacity", "GroupPendingCapacity", "GroupStandbyCapacity",
    "GroupTerminatingCapacity", "GroupTotalCapacity",
  ]

  # Don't wait for healthy instances during apply; check the target group afterwards.
  wait_for_capacity_timeout = "0"

  # Everything the user data reads at first boot must exist before servers launch.
  depends_on = [
    aws_s3_object.jar,
    aws_s3_object.ca1_aws,
    aws_ssm_parameter.db_host,
    aws_ssm_parameter.db_username,
    aws_ssm_parameter.db_password,
    aws_ssm_parameter.coupon_url,
    aws_iam_role_policy.app_access,
    aws_iam_role_policy_attachment.ssm_core,
    aws_lb_listener.http,
  ]
}

# Experiment D - target tracking on average CPU. Created only with -var enable_scaling=true.
# AWS creates and owns the two CloudWatch alarms (AlarmHigh / AlarmLow) behind this policy.
resource "aws_autoscaling_policy" "cpu_target" {
  count = var.enable_scaling ? 1 : 0

  name                      = "${var.name}-cpu-target-tracking"
  autoscaling_group_name    = aws_autoscaling_group.product.name
  policy_type               = "TargetTrackingScaling"
  estimated_instance_warmup = var.instance_warmup

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }
    target_value     = var.cpu_target
    disable_scale_in = false
  }
}
