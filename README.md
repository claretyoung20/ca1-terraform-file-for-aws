# description

## Repository description

Terraform for a Spring Boot microservices lab on AWS: an ALB in front of an auto-scaled Product service, a Coupon service on EC2, RDS MySQL, S3 and SSM Parameter Store, plus a CloudWatch dashboard and the scaling experiments.


```
Provision the full ca1 stack in eu-west-1 as code, replacing the manual
console steps:

- Network: VPC 10.0.0.0/16 across 2 AZs with 2 public and 2 private
  subnets, an internet gateway, and a free S3 gateway endpoint (no NAT)
- Security groups chained by tier: ALB :80 -> Product :9090 ->
  Coupon :9091 -> RDS :3306 (load generator may reach Coupon and RDS)
- Data: RDS MySQL 8.4 (db.t4g.micro, single-AZ, encrypted gp3) in the
  private subnets
- Config: SSM Parameter Store for DB host/username/password
  (SecureString) and the Coupon service URL
- Artifacts: private S3 bucket holding the service JARs and ca1-aws
  scripts, re-uploaded automatically when they change
- Compute: Coupon EC2, k6 load-generator EC2, and the Product service
  behind an internet-facing ALB in an Auto Scaling group (launch
  template, ELB health checks on /actuator/health/liveness)
- Access: IAM role and instance profile with SSM Session Manager (no SSH
  or key pairs) and least-privilege S3/SSM access; IMDSv2 enforced
- Monitoring: CloudWatch dashboard (ALB, target group, ASG, EC2 and RDS
  metrics)
- Experiments: tfvars for baseline (A), 2 and 3 instances (C), CPU
  target-tracking autoscaling (D), failure (E) and pause

State files and local tfvars are git-ignored, so no state or DB
password is committed.

```
## K6 (under ca1-aws)
- include k6 scripts and user data scripts