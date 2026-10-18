# CA1 helper files

Full step-by-step instructions are in the "CA1 Playbook" doc. For a detailed explanation of every script, and how the apps read their settings from the env file, see [SCRIPTS-EXPLAINED.md](SCRIPTS-EXPLAINED.md). Quick map:

| File | Where it runs | What it does |
| --- | --- | --- |
| aws/product-userdata.sh | Launch template user data | Installs Java, pulls the Product JAR from S3, reads config from SSM, runs it as a service, logs startup timings to /var/log/ca1-timing.log |
| aws/coupon-userdata.sh | Coupon EC2 user data | Same for the Coupon Service (port 9091) |
| aws/loadgen-setup.sh | Load-generator EC2 (once) | Installs k6 + Python libs |
| aws/create-dashboard.sh | AWS CloudShell | Superseded by terraform/dashboard.tf (kept for reference) |
| db/dbtool.py | Load-generator EC2 | `init` schema + coupons, `reset` products to 200 rows (before EVERY run), `status` |
| k6/workload.js | Load-generator EC2 | The workload (profiles: smoke, step, surge, steady) |
| k6/run.sh | Load-generator EC2 | Runs one experiment, saves raw data + HTML report + metadata to ~/results/<RUN_ID> |
| analysis/analyse.py | Load-generator or your Mac | Turns results into tables and charts (timeline / steps / compare) |
| experiment-log.csv | You, during experiments | Timestamped log of what you did and saw (UTC) |

Before uploading: set BUCKET in both user-data files.
