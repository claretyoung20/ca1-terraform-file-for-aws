#!/bin/bash
# =====================================================================
# Run one experiment and keep everything about it in ~/results/<RUN_ID>/
#   export BASE_URL=http://<alb-dns>   BUCKET=<your-bucket>
#   ./run.sh <RUN_ID> <PROFILE> [extra k6 args]
# Examples:
#   ./run.sh A-baseline-1i-r1 step
#   ./run.sh C-scaled-2i-r1   step
#   ./run.sh D-elastic-r1     surge -e HIGH_RATE=80
#   ./run.sh E-kill-r1        steady -e RATE=30 -e DURATION=12m
# =====================================================================
set -uo pipefail
RUN_ID=${1:?usage: run.sh RUN_ID PROFILE [k6 args]}; PROFILE=${2:?PROFILE missing}; shift 2
: "${BASE_URL:?export BASE_URL=http://<alb-dns-name> first}"
HERE=$(cd "$(dirname "$0")" && pwd)
OUT=~/results/$RUN_ID; mkdir -p "$OUT"
REGION=${REGION:-eu-west-1}; ASG=${ASG:-ca1-product-asg}

CAP=$(aws autoscaling describe-auto-scaling-groups --region "$REGION" --auto-scaling-group-names "$ASG" \
      --query 'AutoScalingGroups[0].[MinSize,DesiredCapacity,MaxSize,length(Instances)]' --output text 2>/dev/null | tr '\t' '/')
[ -z "$CAP" ] && CAP="unknown"
START=$(date -u +%FT%TZ)
{ echo "run_id=$RUN_ID"; echo "profile=$PROFILE"; echo "extra_args=$*"; echo "start_utc=$START";
  echo "asg_min/desired/max/instances=$CAP"; echo "base_url=$BASE_URL"; } > "$OUT/meta.txt"
echo "Starting $RUN_ID ($PROFILE) at $START UTC, ASG $CAP"

K6_WEB_DASHBOARD=true K6_WEB_DASHBOARD_EXPORT="$OUT/report.html" \
k6 run -e BASE_URL="$BASE_URL" -e PROFILE="$PROFILE" -e RUN_ID="$RUN_ID" "$@" \
   --out csv="$OUT/raw.csv.gz" --summary-export "$OUT/summary.json" \
   "$HERE/workload.js" 2>&1 | tee "$OUT/console.txt"

END=$(date -u +%FT%TZ)
echo "end_utc=$END" >> "$OUT/meta.txt"
echo "$START,$END,$RUN_ID,$PROFILE,$CAP,$*" >> ~/results/run-log.csv
echo "Finished $RUN_ID at $END UTC  ->  $OUT"
if [ -n "${BUCKET:-}" ]; then aws s3 sync ~/results "s3://$BUCKET/results" --quiet && echo "Synced to s3://$BUCKET/results"; fi
