# Complete AWS Deployment Guide
## Two-Step Process: Build AMI → Deploy Cluster

---

## Overview

We use a **custom AMI** approach for the cleanest, most reliable deployment:

1. **Build Custom AMI** (one-time, 20 minutes)
   - Everything pre-installed: OpenROAD, Singularity, SPANK, ML tools
   - Stored as reusable AMI
   
2. **Deploy Cluster** (10-15 minutes)
   - Uses custom AMI
   - Minimal CustomActions (just configuration)
   - Fast, reliable deployment

---

## Step 1: Build Custom AMI (One-Time)

### What Gets Installed

```
Custom AMI Contents:
├── Singularity (container runtime)
├── OpenROAD container (pre-pulled .sif file)
├── SPANK plugin (pre-compiled spank_monitor.so)
├── Python ML tools (scikit-learn, pandas, FastAPI, etc.)
├── Fluent Bit (log processing)
├── Project files (/opt/hpc-optimization/)
└── Helper scripts
```

### Build Command

```bash
chmod +x aws/build-custom-ami.sh
./aws/build-custom-ami.sh
```

### What Happens

1. ✅ Finds base ParallelCluster AMI
2. ✅ Uploads project files to S3
3. ✅ Launches build instance (c5.2xlarge)
4. ✅ Installs Singularity
5. ✅ Pulls OpenROAD Docker → Singularity
6. ✅ Compiles SPANK plugin
7. ✅ Installs Python ML tools
8. ✅ Installs Fluent Bit
9. ✅ Creates AMI snapshot
10. ✅ Terminates build instance
11. ✅ Saves AMI ID to `aws/custom-ami-id.txt`

### Time & Cost

- **Time**: 20 minutes
- **Cost**: ~$0.11 (build instance)
- **Storage**: ~$0.50/month (AMI storage)

### Output

```
AMI ID: ami-0123456789abcdef
Region: us-east-1

Saved to: aws/custom-ami-id.txt
```

---

## Step 2: Deploy Cluster

### Deploy Command

```bash
chmod +x aws/deploy-with-custom-ami.sh
./aws/deploy-with-custom-ami.sh
```

### What Happens

1. ✅ Loads custom AMI ID
2. ✅ Creates cluster configuration
3. ✅ Validates configuration
4. ✅ Deploys ParallelCluster
5. ✅ Head node: Copies files to /shared
6. ✅ Compute nodes: Configures SPANK plugin
7. ✅ Starts prediction API
8. ✅ Cluster ready!

### Time & Cost

- **Time**: 10-15 minutes (faster than standard deployment!)
- **Cost**: ~$0.20/hour idle, ~$1.50/hour with 2 compute nodes

---

## Cluster Architecture

```
┌─────────────────────────────────────────────────────────┐
│                  AWS Parallel Cluster                    │
│                                                          │
│  ┌────────────────────────────────────────────────────┐ │
│  │              Head Node (c5.xlarge)                 │ │
│  │  Custom AMI: ami-xxxxx                             │ │
│  │  ┌──────────────────────────────────────────────┐ │ │
│  │  │  /opt/containers/openroad.sif                │ │ │
│  │  │  /opt/spank/spank_monitor.so                 │ │ │
│  │  │  /opt/hpc-optimization/ (project files)      │ │ │
│  │  └──────────────────────────────────────────────┘ │ │
│  │  ┌──────────────────────────────────────────────┐ │ │
│  │  │  Prediction API (port 8000)                  │ │ │
│  │  └──────────────────────────────────────────────┘ │ │
│  └────────────────────────────────────────────────────┘ │
│                                                          │
│  ┌────────────────────────────────────────────────────┐ │
│  │         Compute Nodes (c5.4xlarge × 0-4)           │ │
│  │  Custom AMI: ami-xxxxx                             │ │
│  │  ┌──────────────────────────────────────────────┐ │ │
│  │  │  SLURM + SPANK Plugin                        │ │ │
│  │  │  Singularity + OpenROAD                      │ │ │
│  │  └──────────────────────────────────────────────┘ │ │
│  └────────────────────────────────────────────────────┘ │
│                                                          │
│  ┌────────────────────────────────────────────────────┐ │
│  │         Shared Storage (EFS)                       │ │
│  │  /shared/                                          │ │
│  │  ├── containers/openroad.sif                      │ │
│  │  ├── spank/spank_monitor.so                       │ │
│  │  ├── hpc-optimization/ (project)                  │ │
│  │  ├── logs/                                         │ │
│  │  ├── metrics/                                      │ │
│  │  └── designs/                                      │ │
│  └────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────┘
```

---

## After Deployment

### 1. SSH to Cluster

```bash
pcluster ssh --cluster-name hpc-optimization \
    -i ~/.ssh/eda-cluster-key.pem \
    --region us-east-1
```

### 2. Verify Installation

```bash
# Check Singularity
singularity --version

# Check OpenROAD container
singularity exec /shared/containers/openroad.sif openroad -version

# Check SPANK plugin
scontrol show config | grep -i spank

# Check SLURM
sinfo
squeue

# Check prediction API
curl http://localhost:8000/health
```

### 3. Submit Test Job

```bash
# Create test job
cat > test_job.sh <<'EOF'
#!/bin/bash
#SBATCH --job-name=openroad-test
#SBATCH --nodes=1
#SBATCH --cpus-per-task=4
#SBATCH --mem=8G
#SBATCH --time=00:05:00
#SBATCH --output=/shared/logs/test_%j.out

# Set design parameters (for SPANK plugin)
export DESIGN_CELL_COUNT=10000
export DESIGN_FREQ_MHZ=100

# Run OpenROAD
singularity exec /shared/containers/openroad.sif openroad -version

echo "Test complete!"
EOF

# Submit job
sbatch test_job.sh

# Check status
squeue
watch squeue

# Check output
tail -f /shared/logs/test_*.out

# Check SPANK metrics
ls /shared/metrics/
cat /shared/metrics/job_*.json
```

### 4. Deploy ML Components

```bash
# Create RDS database (optional - can use SQLite initially)
aws rds create-db-instance \
    --db-instance-identifier hpc-metrics \
    --db-instance-class db.t3.micro \
    --engine postgres \
    --master-username admin \
    --master-user-password YourSecurePassword \
    --allocated-storage 20

# Import existing metrics
cd /shared/hpc-optimization
python3 scripts/import_metrics.py

# Train models
python3 prediction/train_model.py

# Test prediction API
curl -X POST http://localhost:8000/predict \
    -H "Content-Type: application/json" \
    -d '{
        "cell_count": 500000,
        "net_count": 450000,
        "clock_freq_mhz": 500,
        "utilization_target": 0.70
    }'
```

---

## Advantages of Custom AMI Approach

### vs. Standard Deployment

| Aspect | Standard | Custom AMI | Benefit |
|--------|----------|------------|---------|
| **Boot Time** | 5-10 min | 2-3 min | ✅ 2× faster |
| **Reliability** | CustomActions can fail | Pre-tested | ✅ More reliable |
| **Network Dependency** | Downloads on every boot | Pre-cached | ✅ No download failures |
| **Consistency** | Varies by download time | Identical | ✅ Reproducible |
| **Debugging** | Hard to debug failures | Test once | ✅ Easier troubleshooting |

### Cost Comparison

**Standard Deployment**:
- Every node boot: 5-10 min × $0.68/hour = $0.06-0.11 wasted
- 10 nodes × 20 boots/day = $12-22/day wasted = **$360-660/month**

**Custom AMI**:
- AMI storage: **$0.50/month**
- Node boot: 2-3 min (minimal waste)
- **Savings: $360-660/month**

---

## Troubleshooting

### AMI Build Fails

**Check logs**:
```bash
# SSH to build instance (before it terminates)
ssh -i ~/.ssh/eda-cluster-key.pem ec2-user@<PUBLIC_IP>

# Check setup script output
tail -f /tmp/ami-setup.log
```

**Common issues**:
- Singularity install fails → Check EPEL repo
- OpenROAD pull fails → Check Docker Hub availability
- SPANK compile fails → Check SLURM headers installed

### Cluster Deployment Fails

**Check CloudFormation**:
```bash
aws cloudformation describe-stack-events \
    --stack-name hpc-optimization \
    --region us-east-1
```

**Check CloudWatch logs**:
```bash
aws logs tail /aws/parallelcluster/hpc-optimization-* \
    --since 30m \
    --follow
```

### SPANK Plugin Not Working

**Check plugin loaded**:
```bash
scontrol show config | grep -i spank
# Should show: PlugStackConfig = /opt/slurm/etc/plugstack.conf
```

**Check plugin file**:
```bash
ls -l /shared/spank/spank_monitor.so
ls -l /opt/slurm/etc/plugstack.conf
cat /opt/slurm/etc/plugstack.conf
```

**Restart SLURM**:
```bash
sudo systemctl restart slurmd  # On compute nodes
sudo systemctl restart slurmctld  # On head node
```

---

## Cleanup

### Delete Cluster

```bash
pcluster delete-cluster \
    --cluster-name hpc-optimization \
    --region us-east-1
```

### Delete Custom AMI (Optional)

```bash
# Get AMI ID
AMI_ID=$(cat aws/custom-ami-id.txt | grep AMI_ID | cut -d'=' -f2)

# Deregister AMI
aws ec2 deregister-image --image-id $AMI_ID --region us-east-1

# Delete snapshot
SNAPSHOT_ID=$(aws ec2 describe-images --image-ids $AMI_ID \
    --query 'Images[0].BlockDeviceMappings[0].Ebs.SnapshotId' \
    --output text --region us-east-1)
aws ec2 delete-snapshot --snapshot-id $SNAPSHOT_ID --region us-east-1
```

### Delete S3 Bucket

```bash
BUCKET_NAME="hpc-optimization-$(aws sts get-caller-identity --query Account --output text)"
aws s3 rb s3://$BUCKET_NAME --force
```

---

## Summary

### Complete Workflow

```
1. Build Custom AMI (one-time)
   └─> ./aws/build-custom-ami.sh
       └─> Saves AMI ID to aws/custom-ami-id.txt

2. Deploy Cluster (repeatable)
   └─> ./aws/deploy-with-custom-ami.sh
       └─> Uses custom AMI
       └─> Cluster ready in 10-15 min

3. Use Cluster
   └─> SSH, submit jobs, collect metrics
   └─> Train models, optimize resources

4. Cleanup
   └─> Delete cluster
   └─> (Optional) Delete AMI
```

### Key Benefits

- ✅ **Fast deployment**: 10-15 min vs 20-30 min
- ✅ **Reliable**: Everything pre-tested
- ✅ **Cost-effective**: Saves $360-660/month
- ✅ **Reproducible**: Same AMI every time
- ✅ **Easy to update**: Rebuild AMI with changes

### Next Steps

1. Build custom AMI: `./aws/build-custom-ami.sh`
2. Deploy cluster: `./aws/deploy-with-custom-ami.sh`
3. Test workloads
4. Collect metrics
5. Train models
6. Optimize!

---

**Ready to deploy? Start with Step 1: Build Custom AMI**
