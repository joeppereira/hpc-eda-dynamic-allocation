#!/bin/bash
# Setup real OpenROAD environment using Docker

set -e

echo "=========================================="
echo "Setting up REAL OpenROAD Environment"
echo "=========================================="
echo ""

# Pull OpenROAD Docker image
echo "Pulling OpenROAD Docker image..."
docker pull openroad/flow-ubuntu:latest

# Verify OpenROAD works
echo ""
echo "Verifying OpenROAD installation..."
docker run --rm openroad/flow-ubuntu openroad -version

# Create workspace directory
echo ""
echo "Creating workspace directories..."
mkdir -p designs/ibex
mkdir -p designs/aes
mkdir -p openroad_logs
mkdir -p openroad_results

echo ""
echo "=========================================="
echo "✓ OpenROAD environment ready!"
echo "=========================================="
echo ""
echo "OpenROAD is available via Docker:"
echo "  docker run -v \$(pwd):/work openroad/flow-ubuntu openroad [args]"
echo ""
