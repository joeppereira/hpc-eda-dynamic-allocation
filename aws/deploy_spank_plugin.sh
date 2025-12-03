#!/bin/bash
# Deploy real SPANK dynamic allocation plugin to AWS ParallelCluster

set -e

echo "════════════════════════════════════════════════════════════"
echo "  SPANK Dynamic Allocation Plugin - Deployment"
echo "════════════════════════════════════════════════════════════"
echo ""

# Check if running on head node
if [ ! -f /opt/slurm/bin/scontrol ]; then
    echo "ERROR: This must be run on the SLURM head node"
    exit 1
fi

# Find SLURM directories
SLURM_INCLUDE="/opt/slurm/include"
SLURM_LIB="/opt/slurm/lib/slurm"
PLUGSTACK_CONF="/opt/slurm/etc/plugstack.conf"

if [ ! -d "$SLURM_INCLUDE" ]; then
    echo "ERROR: SLURM include directory not found: $SLURM_INCLUDE"
    exit 1
fi

echo "Step 1: Compiling SPANK plugin..."
echo "────────────────────────────────────────────────────────────"

# Copy source to temp location
WORK_DIR="/tmp/spank_build_$$"
mkdir -p $WORK_DIR
cp spank/spank_dynamic_alloc.c $WORK_DIR/

cd $WORK_DIR

# Compile the plugin
gcc -shared -fPIC \
    -I${SLURM_INCLUDE} \
    -o spank_dynamic_alloc.so \
    spank_dynamic_alloc.c \
    -lpthread

if [ $? -ne 0 ]; then
    echo "ERROR: Compilation failed"
    exit 1
fi

echo "✓ Compilation successful"
echo ""

echo "Step 2: Installing plugin..."
echo "────────────────────────────────────────────────────────────"

# Create plugin directory if needed
sudo mkdir -p $SLURM_LIB

# Install the plugin
sudo cp spank_dynamic_alloc.so $SLURM_LIB/
sudo chmod 755 $SLURM_LIB/spank_dynamic_alloc.so

echo "✓ Plugin installed to: $SLURM_LIB/spank_dynamic_alloc.so"
echo ""

echo "Step 3: Configuring SLURM..."
echo "────────────────────────────────────────────────────────────"

# Backup existing plugstack.conf if it exists
if [ -f "$PLUGSTACK_CONF" ]; then
    sudo cp $PLUGSTACK_CONF ${PLUGSTACK_CONF}.backup.$(date +%s)
    echo "✓ Backed up existing plugstack.conf"
fi

# Create or update plugstack.conf
sudo tee $PLUGSTACK_CONF > /dev/null << 'EOF'
# SPANK Plugin Configuration
# Dynamic memory allocation based on design parameters

required ${SLURM_LIB}/spank_dynamic_alloc.so
EOF

echo "✓ Updated $PLUGSTACK_CONF"
echo ""

echo "Step 4: Restarting SLURM services..."
echo "────────────────────────────────────────────────────────────"

# Restart slurmctld on head node
sudo systemctl restart slurmctld
echo "✓ Restarted slurmctld"

# Restart slurmd on compute nodes (if running locally)
if systemctl is-active --quiet slurmd; then
    sudo systemctl restart slurmd
    echo "✓ Restarted slurmd"
fi

echo ""
echo "Step 5: Verification..."
echo "────────────────────────────────────────────────────────────"

# Check if plugin is loaded
sleep 2
if sudo grep -q "spank_dynamic_alloc" /var/log/slurm/slurmctld.log 2>/dev/null; then
    echo "✓ Plugin loaded successfully"
else
    echo "⚠  Could not verify plugin load (check /var/log/slurm/slurmctld.log)"
fi

# Show plugin info
echo ""
echo "Plugin details:"
ls -lh $SLURM_LIB/spank_dynamic_alloc.so

echo ""
echo "════════════════════════════════════════════════════════════"
echo "  SPANK Plugin Deployment Complete!"
echo "════════════════════════════════════════════════════════════"
echo ""
echo "Usage:"
echo "  sbatch --gates=50000 job.sh"
echo "  sbatch --gates=100000 job.sh"
echo ""
echo "The plugin will:"
echo "  1. Detect the --gates parameter"
echo "  2. Calculate required memory (base + gates*0.08 + 20% buffer)"
echo "  3. Adjust memory limit if SLURM allocation is insufficient"
echo "  4. Log all actions to /var/log/slurm/slurmd.log"
echo ""
echo "To test:"
echo "  ./aws/test_spank_plugin.sh"
echo ""

# Cleanup
cd /
rm -rf $WORK_DIR
