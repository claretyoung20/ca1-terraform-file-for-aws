#!/bin/bash
# =====================================================================
# CA1 - Launch template USER DATA for the Product Service
# Amazon Linux 2023. Runs once as root when an instance first boots.
# Paste the whole file into: Launch template > Advanced details > User data
# Edit ONLY the three variables below.
# =====================================================================
set -euo pipefail                     # no "set -x": it would print the DB password to the log
exec > >(tee -a /var/log/ca1-userdata.log) 2>&1

REGION="eu-west-1"
BUCKET="ca1-artifacts-nyoung-2026"   # change here AND in the other user-data file if you pick a different name
JAR_KEY="productservice.jar"          # object name of the JAR in the bucket

stamp() { echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) $1" >> /var/log/ca1-timing.log; }
stamp "userdata-start"

# 1. Java runtime
dnf install -y java-17-amazon-corretto-headless
stamp "java-installed"

# 2. Who am I? (IMDSv2)
TOKEN=$(curl -sX PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 300")
md() { curl -s -H "X-aws-ec2-metadata-token: $TOKEN" "http://169.254.169.254/latest/meta-data/$1"; }
INSTANCE_ID=$(md instance-id)
AZ=$(md placement/availability-zone)

# 3. Application user + JAR from S3
useradd --system --no-create-home --shell /sbin/nologin app 2>/dev/null || true
mkdir -p /opt/productservice
aws s3 cp "s3://${BUCKET}/${JAR_KEY}" /opt/productservice/app.jar --region "$REGION"
chown -R app:app /opt/productservice
stamp "jar-downloaded"

# 4. Configuration + secrets from SSM Parameter Store (nothing secret is stored in this script)
p() { aws ssm get-parameter --region "$REGION" --name "$1" --with-decryption --query Parameter.Value --output text; }
DB_HOST=$(p /ca1/db/host)
cat > /etc/productservice.env <<ENV
SPRING_DATASOURCE_URL=jdbc:mysql://${DB_HOST}:3306/servicedb
SPRING_DATASOURCE_USERNAME=$(p /ca1/db/username)
SPRING_DATASOURCE_PASSWORD=$(p /ca1/db/password)
COUPONSERVICE_URL=$(p /ca1/coupon/url)
SPRING_JPA_HIBERNATE_DDL_AUTO=none
MANAGEMENT_ENDPOINT_HEALTH_PROBES_ENABLED=true
INSTANCE_ID=${INSTANCE_ID}
INSTANCE_AZ=${AZ}
ENV
chmod 600 /etc/productservice.env

# 5. Run as a systemd service (restarts if the JVM crashes)
cat > /etc/systemd/system/productservice.service <<'UNIT'
[Unit]
Description=Product Service (CA1)
After=network-online.target
Wants=network-online.target

[Service]
User=app
EnvironmentFile=/etc/productservice.env
ExecStart=/usr/bin/java -Xms256m -Xmx512m -jar /opt/productservice/app.jar
Restart=on-failure
RestartSec=5
SuccessExitStatus=143

[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload
systemctl enable --now productservice
stamp "service-started"

# 6. Record when the app itself became healthy (evidence for startup-time analysis)
for i in $(seq 1 150); do
  if curl -sf http://localhost:9090/actuator/health/liveness > /dev/null; then
    stamp "app-healthy"; exit 0
  fi
  sleep 2
done
stamp "app-NOT-healthy-after-300s"
