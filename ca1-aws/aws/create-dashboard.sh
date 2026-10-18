#!/bin/bash
# =====================================================================
# Creates the CloudWatch dashboard "ca1-dashboard". Run in AWS CloudShell
# (eu-west-1) AFTER the ALB, target group, ASG, RDS and Coupon EC2 exist.
# Re-run it any time; it overwrites the dashboard.
# =====================================================================
set -euo pipefail
REGION=${REGION:-eu-west-1}
ALB_NAME=${ALB_NAME:-ca1-alb}; TG_NAME=${TG_NAME:-ca1-product-tg}
ASG=${ASG:-ca1-product-asg}; DB_ID=${DB_ID:-ca1-db}; COUPON_TAG=${COUPON_TAG:-ca1-coupon}

ALB_ARN=$(aws elbv2 describe-load-balancers --region $REGION --names $ALB_NAME --query 'LoadBalancers[0].LoadBalancerArn' --output text)
TG_ARN=$(aws elbv2 describe-target-groups --region $REGION --names $TG_NAME --query 'TargetGroups[0].TargetGroupArn' --output text)
LB=${ALB_ARN#*:loadbalancer/}          # app/ca1-alb/xxxxxxxx
TG=${TG_ARN##*:}                       # targetgroup/ca1-product-tg/yyyyyyyy
COUPON_ID=$(aws ec2 describe-instances --region $REGION \
  --filters "Name=tag:Name,Values=$COUPON_TAG" "Name=instance-state-name,Values=running" \
  --query 'Reservations[0].Instances[0].InstanceId' --output text)
echo "LB=$LB  TG=$TG  COUPON=$COUPON_ID"

w() { # x y title stat metrics-json
  echo "{\"type\":\"metric\",\"x\":$1,\"y\":$2,\"width\":12,\"height\":6,\"properties\":{\"title\":\"$3\",\"region\":\"$REGION\",\"period\":60,\"view\":\"timeSeries\",\"stacked\":false,\"stat\":\"$4\",\"metrics\":$5}}"
}
BODY="{\"widgets\":[
$(w 0 0  'ALB - requests per minute' Sum "[[\"AWS/ApplicationELB\",\"RequestCount\",\"LoadBalancer\",\"$LB\"]]"),
$(w 12 0 'ALB - 5xx per minute (target vs load balancer)' Sum "[[\"AWS/ApplicationELB\",\"HTTPCode_Target_5XX_Count\",\"LoadBalancer\",\"$LB\"],[\"AWS/ApplicationELB\",\"HTTPCode_ELB_5XX_Count\",\"LoadBalancer\",\"$LB\"]]"),
$(w 0 6  'ALB - target response time (s)' p95 "[[\"AWS/ApplicationELB\",\"TargetResponseTime\",\"LoadBalancer\",\"$LB\",{\"stat\":\"p50\",\"label\":\"p50\"}],[\"AWS/ApplicationELB\",\"TargetResponseTime\",\"LoadBalancer\",\"$LB\",{\"stat\":\"p95\",\"label\":\"p95\"}]]"),
$(w 12 6 'Target group - healthy vs unhealthy targets' Average "[[\"AWS/ApplicationELB\",\"HealthyHostCount\",\"TargetGroup\",\"$TG\",\"LoadBalancer\",\"$LB\",{\"stat\":\"Minimum\"}],[\"AWS/ApplicationELB\",\"UnHealthyHostCount\",\"TargetGroup\",\"$TG\",\"LoadBalancer\",\"$LB\",{\"stat\":\"Maximum\"}]]"),
$(w 0 12 'ASG - desired / in service / pending' Average "[[\"AWS/AutoScaling\",\"GroupDesiredCapacity\",\"AutoScalingGroupName\",\"$ASG\"],[\"AWS/AutoScaling\",\"GroupInServiceInstances\",\"AutoScalingGroupName\",\"$ASG\"],[\"AWS/AutoScaling\",\"GroupPendingInstances\",\"AutoScalingGroupName\",\"$ASG\"]]"),
$(w 12 12 'Product ASG - CPU % (average and max instance)' Average "[[\"AWS/EC2\",\"CPUUtilization\",\"AutoScalingGroupName\",\"$ASG\",{\"stat\":\"Average\",\"label\":\"average\"}],[\"AWS/EC2\",\"CPUUtilization\",\"AutoScalingGroupName\",\"$ASG\",{\"stat\":\"Maximum\",\"label\":\"max\"}]]"),
$(w 0 18 'Requests per target per minute' Sum "[[\"AWS/ApplicationELB\",\"RequestCountPerTarget\",\"TargetGroup\",\"$TG\",\"LoadBalancer\",\"$LB\"]]"),
$(w 12 18 'Coupon EC2 - CPU %' Average "[[\"AWS/EC2\",\"CPUUtilization\",\"InstanceId\",\"$COUPON_ID\"]]"),
$(w 0 24 'RDS - CPU %' Average "[[\"AWS/RDS\",\"CPUUtilization\",\"DBInstanceIdentifier\",\"$DB_ID\"]]"),
$(w 12 24 'RDS - open connections' Maximum "[[\"AWS/RDS\",\"DatabaseConnections\",\"DBInstanceIdentifier\",\"$DB_ID\"]]")
]}"
echo "$BODY" | python3 -m json.tool > /dev/null     # fail early if the JSON is malformed
aws cloudwatch put-dashboard --region $REGION --dashboard-name ca1-dashboard --dashboard-body "$BODY"
echo "Open: https://$REGION.console.aws.amazon.com/cloudwatch/home?region=$REGION#dashboards/dashboard/ca1-dashboard"
