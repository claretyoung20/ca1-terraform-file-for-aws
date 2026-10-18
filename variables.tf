variable "region" {
  description = "AWS region for every resource."
  type        = string
  default     = "eu-west-1"
}

variable "name" {
  description = "Name prefix, same as the console's 'Name tag auto-generation'."
  type        = string
  default     = "ca1"
}

variable "vpc_cidr" {
  description = "IPv4 CIDR for the VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "bucket_name" {
  description = "Artifacts bucket. If you change it, also change BUCKET in ca1-aws/aws/*-userdata.sh."
  type        = string
  default     = "ca1-artifacts-nyoung-2026"
}

variable "bucket_force_destroy" {
  description = "Let 'terraform destroy' delete the bucket even when it still holds objects (JARs, results)."
  type        = bool
  default     = false
}

variable "db_instance_class" {
  description = "RDS instance class (cheapest burstable)."
  type        = string
  default     = "db.t4g.micro"
}

variable "loadgen_instance_type" {
  description = "Load-generator EC2 instance type. c6a.xlarge (4 vCPU, 1.56 Gbit/s baseline, not burstable) so the tester is never the bottleneck at ~3000 req/s; t3a.small was enough only for the smoke test and pilots."
  type        = string
  default     = "c6a.xlarge"
}

variable "coupon_instance_type" {
  description = "Coupon service EC2 instance type."
  type        = string
  default     = "t3a.micro"
}

variable "product_instance_type" {
  description = "Product service instance type (launch template)."
  type        = string
  default     = "t3a.micro"
}

variable "product_asg_min" {
  description = "Product ASG minimum size (baseline: 1)."
  type        = number
  default     = 1
}

variable "product_asg_max" {
  description = "Product ASG maximum size (baseline: 1)."
  type        = number
  default     = 1
}

variable "product_asg_desired" {
  description = "Product ASG desired capacity (baseline: 1)."
  type        = number
  default     = 1
}

variable "enable_scaling" {
  description = "Experiment D: attach the CPU target-tracking policy. While true, Terraform stops managing desired capacity so it never fights the auto-scaler."
  type        = bool
  default     = false
}

variable "cpu_target" {
  description = "Target average CPU % for the target-tracking policy (justify from the baseline results)."
  type        = number
  default     = 50
}

variable "instance_warmup" {
  description = "Seconds a new Product server needs before its metrics count (measured boot-to-healthy time plus margin)."
  type        = number
  default     = 180
}
