#!/bin/bash
# Run REAL OpenROAD in Docker with monitoring

set -e

echo "=========================================="
echo "Running REAL OpenROAD with Docker"
echo "=========================================="
echo ""

# Check Docker is running
if ! docker info > /dev/null 2>&1; then
    echo "ERROR: Docker daemon is not running!"
    echo "Please start Docker Desktop and try again."
    exit 1
fi

# Pull OpenROAD image
echo "Pulling OpenROAD image..."
docker pull openroad/flow-ubuntu:latest

# Verify OpenROAD
echo ""
echo "Verifying OpenROAD installation..."
docker run --rm openroad/flow-ubuntu openroad -version

# Create directories
mkdir -p designs openroad_logs openroad_results data/metrics

# Download OpenROAD-flow-scripts with test designs
if [ ! -d "OpenROAD-flow-scripts" ]; then
    echo ""
    echo "Downloading OpenROAD-flow-scripts..."
    git clone --depth 1 https://github.com/The-OpenROAD-Project/OpenROAD-flow-scripts
fi

cd OpenROAD-flow-scripts

# Run real OpenROAD flow with monitoring
echo ""
echo "=========================================="
echo "Running REAL OpenROAD Flow: GCD Design"
echo "=========================================="

# Run in Docker with volume mount
docker run --rm \
    -v $(pwd):/OpenROAD-flow-scripts \
    -w /OpenROAD-flow-scripts \
    openroad/flow-ubuntu \
    bash -c "make DESIGN_CONFIG=designs/asap7/gcd/config.mk"

echo ""
echo "✓ Real OpenROAD execution complete!"
echo "✓ Logs available in: logs/asap7/gcd/"
echo ""

# Parse real logs
cd ..
echo "Parsing real OpenROAD logs..."
python3 scripts/parse_openroad_logs.py OpenROAD-flow-scripts/logs/asap7/gcd/

echo ""
echo "=========================================="
echo "✓ Real execution and monitoring complete!"
echo "=========================================="
