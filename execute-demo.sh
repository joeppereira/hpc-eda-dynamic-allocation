#!/bin/bash
# Execute Complete Demo on AWS Cluster
# This script documents every step for reproducibility

set -e

echo "=========================================="
echo "HPC Resource Optimization - Live Demo"
echo "=========================================="
echo ""
echo "Started: $(date)"
echo ""

# Configuration
CLUSTER_NAME="hpc-optimization"
REGION="us-east-1"
KEY_FILE="~/.ssh/eda-cluster-key.pem"

# Create demo directories
mkdir -p demo_results/{logs,screenshots,data}

echo "Step 1: Verify cluster is ready..."
STATUS=$(pcluster describe-cluster --cluster-name $CLUSTER_NAME --region $REGION --query 'clusterStatus' --output text)
echo "Cluster status: $STATUS"

if [ "$STATUS" != "CREATE_COMPLETE" ]; then
    echo "❌ Cluster not ready. Status: $STATUS"
    exit 1
fi

echo "✓ Cluster ready"
echo ""

echo "Step 2: Get cluster information..."
pcluster describe-cluster --cluster-name $CLUSTER_NAME --region $REGION > demo_results/data/cluster-info.json
echo "✓ Cluster info saved"
echo ""

echo "Step 3: SSH to cluster and setup..."
echo "Commands to run on cluster:"
echo ""

cat > demo_results/setup-commands.sh <<'SETUP'
#!/bin/bash
# Run these commands on the cluster head node

echo "=== Setting up cluster for demo ==="

# Install Singularity
echo "[1/6] Installing Singularity..."
sudo yum install -y epel-release
sudo yum install -y singularity-ce
singularity --version

# Create directories
echo "[2/6] Creating directories..."
sudo mkdir -p /shared/{containers,logs,metrics,designs,spank}
sudo chmod 777 /shared/{logs,metrics,designs}

# Pull OpenROAD container
echo "[3/6] Pulling OpenROAD container (this takes 5-10 minutes)..."
cd /shared/containers
sudo singularity pull openroad.sif docker://openroad/flow-ubuntu:latest
sudo chmod 644 openroad.sif

# Test OpenROAD
echo "[4/6] Testing OpenROAD..."
singularity exec /shared/containers/openroad.sif openroad -version

# Install stress-ng for workload simulation
echo "[5/6] Installing stress-ng..."
sudo yum install -y stress-ng

# Create test job scripts
echo "[6/6] Creating test job scripts..."
cd /shared

# Small design job
cat > job_small.sh <<'EOF'
#!/bin/bash
#SBATCH --job-name=openroad-small
#SBATCH --nodes=1
#SBATCH --cpus-per-task=4
#SBATCH --mem=8G
#SBATCH --time=00:10:00
#SBATCH --output=/shared/logs/small_%j.out

echo "=========================================="
echo "Small Design Job"
echo "=========================================="
echo "Job ID: $SLURM_JOB_ID"
echo "Started: $(date)"
echo ""

export DESIGN_CELL_COUNT=10000
export DESIGN_FREQ_MHZ=100

echo "Design Parameters:"
echo "  Cell Count: 10,000"
echo "  Frequency: 100 MHz"
echo ""

echo "Resource Request:"
echo "  CPUs: 4"
echo "  Memory: 8GB"
echo "  Time: 10 minutes"
echo ""

echo "Testing OpenROAD..."
singularity exec /shared/containers/openroad.sif openroad -version
echo ""

echo "Simulating synthesis stage (30s)..."
stress-ng --cpu 2 --vm 1 --vm-bytes 2G --timeout 30s --quiet

echo "Simulating placement stage (20s)..."
stress-ng --cpu 3 --vm 1 --vm-bytes 4G --timeout 20s --quiet

echo "Simulating routing stage (10s)..."
stress-ng --cpu 2 --vm 1 --vm-bytes 3G --timeout 10s --quiet

echo ""
echo "Job completed: $(date)"
echo "=========================================="
EOF

# Medium design job
cat > job_medium.sh <<'EOF'
#!/bin/bash
#SBATCH --job-name=openroad-medium
#SBATCH --nodes=1
#SBATCH --cpus-per-task=8
#SBATCH --mem=16G
#SBATCH --time=00:15:00
#SBATCH --output=/shared/logs/medium_%j.out

echo "=========================================="
echo "Medium Design Job"
echo "=========================================="
echo "Job ID: $SLURM_JOB_ID"
echo "Started: $(date)"
echo ""

export DESIGN_CELL_COUNT=100000
export DESIGN_FREQ_MHZ=500

echo "Design Parameters:"
echo "  Cell Count: 100,000"
echo "  Frequency: 500 MHz"
echo ""

echo "Resource Request:"
echo "  CPUs: 8"
echo "  Memory: 16GB"
echo "  Time: 15 minutes"
echo ""

echo "Testing OpenROAD..."
singularity exec /shared/containers/openroad.sif openroad -version
echo ""

echo "Simulating synthesis stage (40s)..."
stress-ng --cpu 4 --vm 1 --vm-bytes 8G --timeout 40s --quiet

echo "Simulating placement stage (30s)..."
stress-ng --cpu 6 --vm 1 --vm-bytes 12G --timeout 30s --quiet

echo "Simulating routing stage (20s)..."
stress-ng --cpu 5 --vm 1 --vm-bytes 10G --timeout 20s --quiet

echo ""
echo "Job completed: $(date)"
echo "=========================================="
EOF

# Large design job
cat > job_large.sh <<'EOF'
#!/bin/bash
#SBATCH --job-name=openroad-large
#SBATCH --nodes=1
#SBATCH --cpus-per-task=16
#SBATCH --mem=32G
#SBATCH --time=00:20:00
#SBATCH --output=/shared/logs/large_%j.out

echo "=========================================="
echo "Large Design Job"
echo "=========================================="
echo "Job ID: $SLURM_JOB_ID"
echo "Started: $(date)"
echo ""

export DESIGN_CELL_COUNT=500000
export DESIGN_FREQ_MHZ=1000

echo "Design Parameters:"
echo "  Cell Count: 500,000"
echo "  Frequency: 1000 MHz"
echo ""

echo "Resource Request:"
echo "  CPUs: 16"
echo "  Memory: 32GB"
echo "  Time: 20 minutes"
echo ""

echo "Testing OpenROAD..."
singularity exec /shared/containers/openroad.sif openroad -version
echo ""

echo "Simulating synthesis stage (60s)..."
stress-ng --cpu 8 --vm 1 --vm-bytes 16G --timeout 60s --quiet

echo "Simulating placement stage (50s)..."
stress-ng --cpu 12 --vm 1 --vm-bytes 24G --timeout 50s --quiet

echo "Simulating routing stage (40s)..."
stress-ng --cpu 10 --vm 1 --vm-bytes 20G --timeout 40s --quiet

echo ""
echo "Job completed: $(date)"
echo "=========================================="
EOF

chmod +x job_*.sh

echo ""
echo "✓ Setup complete!"
echo ""
echo "Next steps:"
echo "  1. Submit jobs: sbatch job_small.sh job_medium.sh job_large.sh"
echo "  2. Monitor: watch -n 2 squeue"
echo "  3. View results: sacct -S today"
SETUP

chmod +x demo_results/setup-commands.sh

echo "✓ Setup script created: demo_results/setup-commands.sh"
echo ""

echo "=========================================="
echo "Demo Execution Instructions"
echo "=========================================="
echo ""
echo "1. SSH to cluster:"
echo "   pcluster ssh --cluster-name $CLUSTER_NAME -i $KEY_FILE --region $REGION"
echo ""
echo "2. Run setup script:"
echo "   bash < demo_results/setup-commands.sh"
echo ""
echo "3. Submit jobs:"
echo "   cd /shared"
echo "   sbatch job_small.sh"
echo "   sbatch job_medium.sh"
echo "   sbatch job_large.sh"
echo ""
echo "4. Monitor jobs:"
echo "   watch -n 2 'squeue; echo \"\"; sacct -S today --format=JobID,JobName,State,AllocCPUS,ReqMem,Elapsed'"
echo ""
echo "5. Analyze results:"
echo "   sacct -S today --format=JobID,JobName,State,AllocCPUS,ReqMem,MaxRSS,Elapsed,CPUTime"
echo ""
echo "=========================================="
echo ""

echo "Demo preparation complete!"
echo "Finished: $(date)"
