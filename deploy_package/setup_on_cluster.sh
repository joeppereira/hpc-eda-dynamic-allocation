#!/bin/bash
# Setup script to run on the cluster head node

set -e

echo "=========================================="
echo "Setting up HPC Resource Optimization"
echo "=========================================="

# Install system dependencies
echo "Installing system dependencies..."
sudo yum install -y python3-pip git

# Install Python dependencies
echo "Installing Python packages..."
pip3 install --user -r requirements.txt

# Install Singularity
echo "Installing Singularity..."
if ! command -v singularity &> /dev/null; then
    sudo yum install -y singularity
fi

# Pull OpenROAD container
echo "Pulling OpenROAD container..."
if [ ! -f openroad.sif ]; then
    singularity pull openroad.sif docker://openroad/flow-ubuntu22.04-builder:latest
fi

# Setup database
echo "Setting up database..."
python3 database/schema.py

echo ""
echo "✓ Setup complete!"
echo ""
