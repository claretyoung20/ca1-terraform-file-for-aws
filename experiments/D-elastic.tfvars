# Experiment D - elasticity: 2 to 4 servers, CPU target tracking.
# cpu_target 50: in A and C the SLO held up to ~65-75% CPU and broke at 85-95%,
#   so 50% leaves headroom to absorb the ~2-3 min it takes a new server to help.
# instance_warmup 120: measured launch-to-healthy ~90 s (userdata log) + 2 health
#   checks x 10 s = ~110 s. Until then the new server's CPU is ignored by the policy.
product_asg_min = 2
product_asg_max = 4
enable_scaling  = true
cpu_target      = 50
instance_warmup = 120
