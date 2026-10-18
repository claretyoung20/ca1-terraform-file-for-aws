# Step 13 - CloudWatch dashboard "ca1-dashboard" (replaces ca1-aws/aws/create-dashboard.sh).
# 1-minute resolution everywhere except the load generator, which uses basic 5-minute monitoring.
# Metric dimensions come straight from the resources, so the dashboard follows any rebuild.

locals {
  lb  = aws_lb.main.arn_suffix                   # app/ca1-alb/...
  tg  = aws_lb_target_group.product.arn_suffix   # targetgroup/ca1-product-tg/...
  asg = aws_autoscaling_group.product.name

  widget = {
    type   = "metric"
    width  = 12
    height = 6
  }
}

resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "${var.name}-dashboard"

  dashboard_body = jsonencode({
    widgets = [
      merge(local.widget, { x = 0, y = 0, properties = {
        title = "ALB - requests per minute", region = var.region, period = 60, stat = "Sum", view = "timeSeries",
        metrics = [["AWS/ApplicationELB", "RequestCount", "LoadBalancer", local.lb]]
      } }),
      merge(local.widget, { x = 12, y = 0, properties = {
        title = "ALB - 5xx per minute (target = app error, ELB = no healthy target / dropped)", region = var.region, period = 60, stat = "Sum", view = "timeSeries",
        metrics = [
          ["AWS/ApplicationELB", "HTTPCode_Target_5XX_Count", "LoadBalancer", local.lb],
          ["AWS/ApplicationELB", "HTTPCode_ELB_5XX_Count", "LoadBalancer", local.lb],
        ]
      } }),
      merge(local.widget, { x = 0, y = 6, properties = {
        title = "ALB - target response time (seconds)", region = var.region, period = 60, view = "timeSeries",
        metrics = [
          ["AWS/ApplicationELB", "TargetResponseTime", "LoadBalancer", local.lb, { stat = "p50", label = "p50" }],
          ["AWS/ApplicationELB", "TargetResponseTime", "LoadBalancer", local.lb, { stat = "p95", label = "p95" }],
        ]
      } }),
      merge(local.widget, { x = 12, y = 6, properties = {
        title = "Target group - healthy vs unhealthy targets", region = var.region, period = 60, view = "timeSeries",
        metrics = [
          ["AWS/ApplicationELB", "HealthyHostCount", "TargetGroup", local.tg, "LoadBalancer", local.lb, { stat = "Minimum" }],
          ["AWS/ApplicationELB", "UnHealthyHostCount", "TargetGroup", local.tg, "LoadBalancer", local.lb, { stat = "Maximum" }],
        ]
      } }),
      merge(local.widget, { x = 0, y = 12, properties = {
        title = "ASG - desired / in service / pending", region = var.region, period = 60, stat = "Average", view = "timeSeries",
        metrics = [
          ["AWS/AutoScaling", "GroupDesiredCapacity", "AutoScalingGroupName", local.asg],
          ["AWS/AutoScaling", "GroupInServiceInstances", "AutoScalingGroupName", local.asg],
          ["AWS/AutoScaling", "GroupPendingInstances", "AutoScalingGroupName", local.asg],
        ]
      } }),
      merge(local.widget, { x = 12, y = 12, properties = {
        title = "Product ASG - CPU % (average = scaling metric, max = busiest server)", region = var.region, period = 60, view = "timeSeries",
        metrics = [
          ["AWS/EC2", "CPUUtilization", "AutoScalingGroupName", local.asg, { stat = "Average", label = "average" }],
          ["AWS/EC2", "CPUUtilization", "AutoScalingGroupName", local.asg, { stat = "Maximum", label = "max" }],
        ]
        annotations = { horizontal = [{ label = "scaling target", value = var.cpu_target }] }
        yAxis       = { left = { min = 0, max = 100 } }
      } }),
      merge(local.widget, { x = 0, y = 18, properties = {
        title = "Requests per Product target per minute", region = var.region, period = 60, stat = "Sum", view = "timeSeries",
        metrics = [["AWS/ApplicationELB", "RequestCountPerTarget", "TargetGroup", local.tg, "LoadBalancer", local.lb]]
      } }),
      merge(local.widget, { x = 12, y = 18, properties = {
        title = "Coupon EC2 - CPU %", region = var.region, period = 60, stat = "Average", view = "timeSeries",
        metrics = [["AWS/EC2", "CPUUtilization", "InstanceId", aws_instance.coupon.id]]
        yAxis   = { left = { min = 0, max = 100 } }
      } }),
      merge(local.widget, { x = 0, y = 24, properties = {
        title = "RDS - CPU %", region = var.region, period = 60, stat = "Average", view = "timeSeries",
        metrics = [["AWS/RDS", "CPUUtilization", "DBInstanceIdentifier", aws_db_instance.main.identifier]]
        yAxis   = { left = { min = 0, max = 100 } }
      } }),
      merge(local.widget, { x = 12, y = 24, properties = {
        title = "RDS - open connections (max_connections = 60)", region = var.region, period = 60, stat = "Maximum", view = "timeSeries",
        metrics = [["AWS/RDS", "DatabaseConnections", "DBInstanceIdentifier", aws_db_instance.main.identifier]]
        annotations = { horizontal = [{ label = "max_connections", value = 60 }] }
      } }),
      merge(local.widget, { x = 0, y = 30, properties = {
        title = "Load generator - CPU % (must stay below ~70%, 5-minute data)", region = var.region, period = 300, stat = "Maximum", view = "timeSeries",
        metrics = [["AWS/EC2", "CPUUtilization", "InstanceId", aws_instance.loadgen.id]]
        annotations = { horizontal = [{ label = "70%", value = 70 }] }
        yAxis       = { left = { min = 0, max = 100 } }
      } }),
      merge(local.widget, { x = 12, y = 30, properties = {
        title = "Product servers - network out (Mbit/s, all servers summed)", region = var.region, period = 60, view = "timeSeries",
        metrics = [
          [{ expression = "m1*8/60/1000000", label = "network out Mbit/s", id = "e1" }],
          ["AWS/EC2", "NetworkOut", "AutoScalingGroupName", local.asg, { id = "m1", stat = "Sum", visible = false }],
        ]
      } }),
      merge(local.widget, { x = 0, y = 36, properties = {
        title = "RDS - network transmit (Mbit/s, data sent to the apps)", region = var.region, period = 60, view = "timeSeries",
        metrics = [
          [{ expression = "m2*8/1000000", label = "RDS transmit Mbit/s", id = "e2" }],
          ["AWS/RDS", "NetworkTransmitThroughput", "DBInstanceIdentifier", aws_db_instance.main.identifier, { id = "m2", stat = "Average", visible = false }],
        ]
      } }),
    ]
  })
}
