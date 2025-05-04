#!/bin/bash
set -e

# Create mock directories for testing
mkdir -p /tmp/mock-home/LinuxMCE
mkdir -p /tmp/mock-home/LinuxMCE-Addons
mkdir -p /tmp/mock-home/mysql-data

# Export environment variables for testing
export HOME="/tmp/mock-home"
export PROJECT_NAME="lmce-test"
export UBUNTU_VERSION="22.04"
export PROJECT_DIR="/tmp/mock-output"
export MYSQL_DIR="/tmp/mock-home/mysql-data"

# Run the setup script with headless settings
chmod +x ./linuxmce-docker-setup.sh
./linuxmce-docker-setup.sh --headless

# Show the result
echo "===== 02proxy Output ====="
cat "$PROJECT_DIR/configs/apt/02proxy"
echo "===== docker-compose.yml Output ====="
cat "$PROJECT_DIR/docker-compose.yml"
