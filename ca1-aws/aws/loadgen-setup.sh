#!/bin/bash
# CA1 - one-off setup of the LOAD GENERATOR instance (Amazon Linux 2023).
# Run in a Session Manager shell:   bash loadgen-setup.sh
set -euo pipefail

sudo dnf install -y python3-pip tar gzip

# k6 (official RPM repo; falls back to the GitHub release tarball)
if ! command -v k6 >/dev/null; then
  if ! (sudo dnf install -y https://dl.k6.io/rpm/repo.rpm && sudo dnf install -y k6); then
    VER=$(curl -s https://api.github.com/repos/grafana/k6/releases/latest | grep -Po '"tag_name":\s*"\K[^"]+')
    curl -sL "https://github.com/grafana/k6/releases/download/${VER}/k6-${VER}-linux-amd64.tar.gz" | tar xz
    sudo mv "k6-${VER}-linux-amd64/k6" /usr/local/bin/k6
  fi
fi
k6 version

# Python libs for the DB helper and the analysis script
pip3 install --user pymysql cryptography pandas matplotlib

mkdir -p ~/results
echo "Load generator ready. Next: export BASE_URL=http://<alb-dns>  and  export BUCKET=<your-bucket>"
