#!/bin/bash
# Setup script for compute nodes
# This runs on each compute node after it's launched

set -e

echo "=== Starting compute node setup ==="

# Update system
echo "Updating system packages..."
apt-get update -y

# Install dependencies
echo "Installing dependencies..."
apt-get install -y \
    build-essential \
    git \
    wget \
    curl \
    python3-pip \
    python3-dev \
    libpq-dev \
    docker.io

# Install Python packages
echo "Installing Python packages..."
pip3 install psutil sqlalchemy psycopg2-binary

# Setup Docker
echo "Setting up Docker..."
systemctl enable docker
systemctl start docker
usermod -aG docker ubuntu

# Pull OpenROAD Docker image
echo "Pulling OpenROAD Docker image..."
docker pull openroad/flow-ubuntu:latest

# Create directories
echo "Creating directories..."
mkdir -p /shared/openroad
mkdir -p /shared/pdks
mkdir -p /shared/metrics
mkdir -p /shared/logs

# Set permissions
chown -R ubuntu:ubuntu /shared/openroad
chown -R ubuntu:ubuntu /shared/metrics
chown -R ubuntu:ubuntu /shared/logs

# Install Fluent Bit for log processing
echo "Installing Fluent Bit..."
curl https://raw.githubusercontent.com/fluent/fluent-bit/master/install.sh | sh

# Copy Fluent Bit configuration
if [ -f /shared/config/fluent-bit.conf ]; then
    cp /shared/config/fluent-bit.conf /etc/fluent-bit/fluent-bit.conf
fi

# Download and install SPANK plugin (if available)
if [ -f /shared/spank/spank_monitor.so ]; then
    echo "Installing SPANK plugin..."
    cp /shared/spank/spank_monitor.so /opt/slurm/lib/slurm/
    
    # Configure SLURM to load plugin
    if [ ! -f /etc/slurm/plugstack.conf ]; then
        echo "required /opt/slurm/lib/slurm/spank_monitor.so" > /etc/slurm/plugstack.conf
    fi
fi

# Install OpenROAD PDKs
echo "Installing PDKs..."
if [ ! -d /shared/pdks/sky130 ]; then
    echo "Downloading SkyWater 130nm PDK..."
    cd /shared/pdks
    git clone --depth 1 https://github.com/google/skywater-pdk.git sky130 || true
fi

# Setup monitoring
echo "Setting up monitoring..."
cat > /etc/systemd/system/resource-monitor.service <<EOF
[Unit]
Description=Resource Monitoring Service
After=network.target

[Service]
Type=simple
User=ubuntu
WorkingDirectory=/shared
ExecStart=/usr/bin/python3 /shared/monitoring/resource_monitor.py
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

# Enable monitoring service (but don't start - SPANK plugin will handle it)
systemctl daemon-reload
# systemctl enable resource-monitor.service

echo "=== Compute node setup complete ==="
echo "Node is ready for SLURM jobs"
