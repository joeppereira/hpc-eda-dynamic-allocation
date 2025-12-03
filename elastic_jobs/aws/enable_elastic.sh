#!/bin/bash
# Enable elastic jobs on AWS ParallelCluster

set -e

echo "=========================================="
echo "Enable SLURM Elastic Jobs"
echo "=========================================="
echo ""

# Check if running on head node
if [ ! -f /opt/slurm/etc/slurm.conf ]; then
    echo "Error: This script must run on the SLURM head node"
    exit 1
fi

echo "Step 1: Backup current configuration"
sudo cp /opt/slurm/etc/slurm.conf /opt/slurm/etc/slurm.conf.backup.$(date +%Y%m%d_%H%M%S)
echo "✓ Backup created"
echo ""

echo "Step 2: Check current elastic configuration"
if grep -q "ElasticPartition" /opt/slurm/etc/slurm.conf; then
    echo "Elastic partition already configured:"
    grep "ElasticPartition" /opt/slurm/etc/slurm.conf
else
    echo "Elastic partition not configured"
fi
echo ""

echo "Step 3: Enable elastic partition"
# Add ElasticPartition=yes to compute partition
sudo sed -i 's/^\(PartitionName=compute.*\)/\1 ElasticPartition=yes/' /opt/slurm/etc/slurm.conf

# Verify
if grep -q "ElasticPartition=yes" /opt/slurm/etc/slurm.conf; then
    echo "✓ Elastic partition enabled"
    grep "PartitionName=compute" /opt/slurm/etc/slurm.conf
else
    echo "✗ Failed to enable elastic partition"
    exit 1
fi
echo ""

echo "Step 4: Validate configuration"
sudo slurmctld -t 2>&1 | head -20
if [ $? -eq 0 ]; then
    echo "✓ Configuration valid"
else
    echo "✗ Configuration has errors"
    echo "Restoring backup..."
    sudo cp /opt/slurm/etc/slurm.conf.backup.* /opt/slurm/etc/slurm.conf
    exit 1
fi
echo ""

echo "Step 5: Restart SLURM controller"
sudo systemctl restart slurmctld
sleep 5

if sudo systemctl is-active --quiet slurmctld; then
    echo "✓ SLURM controller restarted successfully"
else
    echo "✗ SLURM controller failed to restart"
    sudo systemctl status slurmctld
    exit 1
fi
echo ""

echo "Step 6: Verify elastic partition"
scontrol show partition compute | grep -i elastic
echo ""

echo "=========================================="
echo "✓ Elastic Jobs Enabled"
echo "=========================================="
echo ""
echo "Configuration:"
scontrol show partition compute
echo ""
echo "Next steps:"
echo "  1. Install PMIx-enabled MPI: ./install_mpi.sh"
echo "  2. Test elastic jobs: ./test_elastic.sh"
echo ""
