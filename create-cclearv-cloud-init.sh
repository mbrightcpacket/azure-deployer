#!/usr/bin/env bash
set -e

cloud_init_sh="cclearv-ccloud-init.sh"
touch "$cloud_init_sh"

echo '#!/bin/bash' >> "$cloud_init_sh"
echo 'mkdir -p /opt/cloud/' >> "$cloud_init_sh"
echo 'cat <<EOF_DEPLOYER >/opt/cloud/deployer.py' >> "$cloud_init_sh"
cat deployer.py >> "$cloud_init_sh"
echo '' >> "$cloud_init_sh"
echo 'EOF_DEPLOYER' >> "$cloud_init_sh"
echo '' >> "$cloud_init_sh"
echo 'chmod +x /opt/cloud/deployer.py' >> "$cloud_init_sh"
