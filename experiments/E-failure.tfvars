# Experiment E - failure and recovery: 2 servers, room to replace, NO scaling policy,
# so any new server is a replacement for the failed one, not a scale-out.
product_asg_min     = 2
product_asg_desired = 2
product_asg_max     = 4
enable_scaling      = false
