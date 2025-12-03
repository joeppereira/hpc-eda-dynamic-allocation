# Quick Deploy Guide
## Get HPC Optimization Cluster Running in 30 Minutes

---

## TL;DR

```bash
# Step 1: Build custom AMI (20 min, one-time)
./aws/build-custom-ami.sh

# Step 2: Deploy cluster (10 min, repeatable)
./aws/deploy-with-custom-ami.sh

# Step 3: SSH and test
pcluster ssh --cluster-name hpc-optimization -i ~/.ssh/eda-cluster-key.pem --region us-east-1
singularity exec /shared/containers/openroad.sif openroad -version
```

---

## What You Get

✅ **ParallelCluster** with SLURM scheduler
✅ **Singularity** container runtime
✅ **OpenROAD** EDA tool (pre-pulled container)
✅ **SPANK plugin** for resource monitoring
✅ **ML tools** (scikit-learn, pandas, FastAPI)
✅ **Auto-scaling** compute nodes (0-4)
✅ **Shared storage** (EFS)

---

## Prerequisites

- ✅ AWS CLI configured
- ✅ ParallelCluster CLI installed (v3.14.0)
- ✅ EC2 key pair: `eda-cluster-key`
- ✅ VPC and subnet available

---

## Step-by-Step

### 1. Build Custom AMI (One-Time)

```bash
./aws/build-custom-ami.sh
```

**What happens**:
- Launches build instance
- Installs everything (Singularity, OpenROAD, SPANK, ML tools)
- Creates AMI snapshot
- Saves AMI ID to `aws/custom-ami-id.txt`

**Time**: 20 minutes
**Cost**: $0.11

### 2. Deploy Cluster

```bash
./aws/deploy-with-custom-ami.sh
```

**What happens**:
- Creates cluster configuration
- Deploys ParallelCluster
- Configures head node and compute nodes
- Starts prediction API

**Time**: 10-15 minutes
**Cost**: $0.20/hour (idle)

### 3. Verify Deployment

```bash
# SSH to cluster
pcluster ssh --cluster-name hpc-optimization -i ~/.ssh/eda-cluster-key.pem --region us-east-1

# Check installations
singularity --version
singularity exec /shared/containers/openroad.sif openroad -version
sinfo
scontrol show config | grep -i spank
```

### 4. Submit Test Job

```bash
# On cluster head node
sbatch --wrap="singularity exec /shared/containers/openroad.sif openroad -version"

# Check status
squeue
watch squeue

# Check metrics
ls /shared/metrics/
```

---

## Cost Breakdown

| Component | Cost | Notes |
|-----------|------|-------|
| **AMI Build** | $0.11 | One-time |
| **AMI Storage** | $0.50/month | Ongoing |
| **Head Node** | $0.17/hour | Always running |
| **Compute Nodes** | $0.68/hour each | Only when jobs running |
| **EFS Storage** | $0.30/GB-month | Minimal |

**Typical monthly cost**:
- Idle (no jobs): ~$122/month
- Active (2 nodes, 8 hours/day): ~$400/month

---

## Troubleshooting

### AMI Build Fails

```bash
# Check build instance logs
ssh -i ~/.ssh/eda-cluster-key.pem ec2-user@<BUILD_INSTANCE_IP>
tail -f /tmp/ami-setup.log
```

### Cluster Deploy Fails

```bash
# Check CloudFormation events
aws cloudformation describe-stack-events \
    --stack-name hpc-optimization \
    --region us-east-1 | grep -i failed

# Check CloudWatch logs
aws logs tail /aws/parallelcluster/hpc-optimization-* --since 30m
```

### SPANK Plugin Not Working

```bash
# On compute node
sudo systemctl status slurmd
scontrol show config | grep -i spank
ls -l /shared/spank/spank_monitor.so
```

---

## Cleanup

```bash
# Delete cluster
pcluster delete-cluster --cluster-name hpc-optimization --region us-east-1

# Delete S3 bucket
aws s3 rb s3://hpc-optimization-$(aws sts get-caller-identity --query Account --output text) --force

# (Optional) Delete custom AMI
AMI_ID=$(cat aws/custom-ami-id.txt | grep AMI_ID | cut -d'=' -f2)
aws ec2 deregister-image --image-id $AMI_ID --region us-east-1
```

---

## Next Steps

1. ✅ Deploy cluster (done!)
2. ⏳ Submit OpenROAD jobs
3. ⏳ Collect metrics
4. ⏳ Train ML models
5. ⏳ Enable dynamic resource allocation
6. ⏳ Measure efficiency improvements

---

## Full Documentation

- **Complete Guide**: `aws/COMPLETE_DEPLOYMENT_GUIDE.md`
- **Singularity Details**: `aws/DEPLOYMENT_WITH_SINGULARITY.md`
- **SLURM Best Practices**: `aws/SLURM_BEST_PRACTICES.md`
- **Feature Comparison**: `aws/FEATURE_COMPARISON.md`

---

**Ready? Run: `./aws/build-custom-ami.sh`**
