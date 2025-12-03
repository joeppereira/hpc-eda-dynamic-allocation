#!/bin/bash
# Quick Demo Execution Script
# Run this to execute complete demo on current cluster

set -e

CLUSTER_NAME="hpc-optimization"
REGION="us-east-1"
KEY_FILE="~/.ssh/eda-cluster-key.pem"

echo "=========================================="
echo "HPC Resource Optimization - Quick Demo"
echo "=========================================="
echo ""
echo "Cluster: $CLUSTER_NAME"
echo "Region: $REGION"
echo "Started: $(date)"
echo ""

# Create demo results directory
mkdir -p demo_results/{logs,data,screenshots}

# Step 1: Verify cluster
echo "Step 1: Verifying cluster status..."
STATUS=$(pcluster describe-cluster --cluster-name $CLUSTER_NAME --region $REGION --query 'clusterStatus' --output text)
echo "Status: $STATUS"

if [ "$STATUS" != "CREATE_COMPLETE" ]; then
    echo "❌ Cluster not ready"
    exit 1
fi

echo "✓ Cluster ready"
echo ""

# Step 2: Get cluster info
echo "Step 2: Getting cluster information..."
pcluster describe-cluster --cluster-name $CLUSTER_NAME --region $REGION \
    > demo_results/data/cluster-info.json

HEAD_IP=$(pcluster describe-cluster --cluster-name $CLUSTER_NAME --region $REGION \
    --query 'headNode.publicIpAddress' --output text)

echo "Head node IP: $HEAD_IP"
echo ""

# Step 3: Create setup commands
echo "Step 3: Creating setup script for cluster..."

cat > demo_results/cluster-setup.sh <<'CLUSTERSETUP'
#!/bin/bash
set -e

echo "=== Setting up cluster for demo ==="
echo "Started: $(date)"
echo ""

# Install Singularity
echo "[1/5] Installing Singularity..."
sudo yum install -y epel-release
sudo yum install -y singularity-ce
singularity --version
echo ""

# Install stress-ng for workload simulation
echo "[2/5] Installing stress-ng..."
sudo yum install -y stress-ng
echo ""

# Create directories
echo "[3/5] Creating directories..."
sudo mkdir -p /shared/{containers,logs,metrics,designs}
sudo chmod 777 /shared/{logs,metrics,designs}
echo ""

# Pull OpenROAD container
echo "[4/5] Pulling OpenROAD container (5-10 minutes)..."
cd /shared/containers
sudo singularity pull openroad.sif docker://openroad/flow-ubuntu:latest
sudo chmod 644 openroad.sif
echo ""

# Test OpenROAD
echo "[5/5] Testing OpenROAD..."
singularity exec /shared/containers/openroad.sif openroad -version
echo ""

echo "✓ Setup complete!"
echo "Finished: $(date)"
CLUSTERSETUP

chmod +x demo_results/cluster-setup.sh

echo "✓ Setup script created"
echo ""

# Step 4: Instructions
echo "=========================================="
echo "Next Steps - Execute on Cluster"
echo "=========================================="
echo ""
echo "1. SSH to cluster:"
echo "   pcluster ssh --cluster-name $CLUSTER_NAME -i $KEY_FILE --region $REGION"
echo ""
echo "2. Copy and run setup script:"
cat demo_results/cluster-setup.sh
echo ""
echo "3. After setup, create and submit test jobs:"
echo ""
cat > demo_results/demo-jobs.sh <<'DEMOJOBS'
#!/bin/bash
# Create and submit demo jobs

cd /shared

# Job 1: Small design
cat > job_small.sh <<'EOF'
#!/bin/bash
#SBATCH --job-name=small
#SBATCH --cpus-per-task=4
#SBATCH --mem=8G
#SBATCH --time=00:05:00
#SBATCH --output=/shared/logs/small_%j.out

echo "=== Small Design Job ==="
echo "Job ID: $SLURM_JOB_ID"
echo "Requested: 4 CPUs, 8GB RAM"
echo "Design: 10K cells, 100MHz"
echo ""
singularity exec /shared/containers/openroad.sif openroad -version
echo ""
echo "Simulating workload..."
stress-ng --cpu 2 --vm 1 --vm-bytes 4G --timeout 30s --quiet
echo "Completed: $(date)"
EOF

# Job 2: Medium design
cat > job_medium.sh <<'EOF'
#!/bin/bash
#SBATCH --job-name=medium
#SBATCH --cpus-per-task=8
#SBATCH --mem=16G
#SBATCH --time=00:05:00
#SBATCH --output=/shared/logs/medium_%j.out

echo "=== Medium Design Job ==="
echo "Job ID: $SLURM_JOB_ID"
echo "Requested: 8 CPUs, 16GB RAM"
echo "Design: 100K cells, 500MHz"
echo ""
singularity exec /shared/containers/openroad.sif openroad -version
echo ""
echo "Simulating workload..."
stress-ng --cpu 5 --vm 1 --vm-bytes 10G --timeout 40s --quiet
echo "Completed: $(date)"
EOF

# Job 3: Large design
cat > job_large.sh <<'EOF'
#!/bin/bash
#SBATCH --job-name=large
#SBATCH --cpus-per-task=16
#SBATCH --mem=32G
#SBATCH --time=00:05:00
#SBATCH --output=/shared/logs/large_%j.out

echo "=== Large Design Job ==="
echo "Job ID: $SLURM_JOB_ID"
echo "Requested: 16 CPUs, 32GB RAM"
echo "Design: 500K cells, 1GHz"
echo ""
singularity exec /shared/containers/openroad.sif openroad -version
echo ""
echo "Simulating workload..."
stress-ng --cpu 10 --vm 1 --vm-bytes 20G --timeout 50s --quiet
echo "Completed: $(date)"
EOF

chmod +x job_*.sh

# Submit all jobs
echo "Submitting jobs..."
sbatch job_small.sh
sbatch job_medium.sh
sbatch job_large.sh

echo ""
echo "Jobs submitted! Monitor with:"
echo "  watch -n 2 'squeue; echo \"\"; sacct -S today --format=JobID,JobName,State,AllocCPUS,ReqMem,Elapsed'"
DEMOJOBS

chmod +x demo_results/demo-jobs.sh

echo ""
echo "4. Monitor and analyze:"
echo "   squeue"
echo "   sacct -S today --format=JobID,JobName,State,AllocCPUS,ReqMem,MaxRSS,Elapsed"
echo ""
echo "5. View results:"
echo "   cat /shared/logs/*.out"
echo ""
echo "=========================================="
echo "Demo script ready!"
echo "=========================================="
echo ""
echo "Files created:"
echo "  - demo_results/cluster-setup.sh"
echo "  - demo_results/demo-jobs.sh"
echo ""
echo "Start demo: SSH to cluster and run the scripts above"
echo ""
