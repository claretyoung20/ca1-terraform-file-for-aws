# Experiment configurations

Change the Product tier ONLY through these files, never in the console
(a later `terraform apply` would silently undo console changes).

    terraform apply -var-file=experiments/A-baseline.tfvars
    terraform apply -var-file=experiments/C-2-instances.tfvars
    terraform apply -var-file=experiments/C-3-instances.tfvars
    terraform apply -var-file=experiments/D-elastic.tfvars
    terraform apply -var-file=experiments/E-failure.tfvars
    terraform apply -var-file=experiments/pause.tfvars

After each apply: wait until all targets are healthy for >= 5 minutes, then
`terraform output product_asg_config` and copy the line into experiment-log.csv.
