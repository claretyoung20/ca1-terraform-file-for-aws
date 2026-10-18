# Between sessions: no Product servers (ALB, RDS and the other EC2s are paused separately).
product_asg_min     = 0
product_asg_desired = 0
product_asg_max     = 1
enable_scaling      = false
