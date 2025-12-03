# Phase 2: AWS Deployment - Ready to Deploy

## ✅ Phase 1 Complete

**Local Development Achievements:**
- Database schema and monitoring infrastructure ✓
- 7 jobs with 21 stage records collected ✓
- Ridge regression models trained ✓
- Memory prediction: R² = 0.95 (excellent!) ✓
- Infrastructure validated and working ✓

## 📦 Phase 2 Deployment Files Created

### 1. Cluster Configuration
**File**: `aws/cluster-config.yaml`
- Head node: c5.xlarge (4 vCPU, 8GB RAM)
- Compute nodes: c5.4xlarge (16 vCPU, 32GB RAM)
- Auto-scaling: 0-10 nodes
- Shared storage: EFS
- SLURM scheduler configured
- CloudWatch monitoring enabled

### 2. Setup Scripts
**Files**:
- `aws/scripts/setup-compute-node.sh` - Installs OpenROAD, Docker, Fluent Bit, SPANK plugin
- `aws/scripts/setup-head-node.sh` - Sets up prediction API, job optimizer, database connection

### 3. Deployment Guide
**File**: `aws/DEPLOYMENT_GUIDE.md`
- Complete step-by-step instructions
- AWS CLI commands
- Cost estimates ($515-1,385/month)
- Troubleshooting guide
- Cleanup procedures

## 🚀 Deployment Steps Overview

### Prerequisites (5 minutes)
1. AWS account with permissions
2. AWS CLI installed and configured
3. EC2 key pair created
4. VPC and subnet configured

### Infrastructure Setup (30 minutes)
1. Install ParallelCluster CLI
2. Create S3 bucket for scripts
3. Create RDS PostgreSQL database
4. Update cluster configuration with your IDs

### Cluster Deployment (15 minutes)
1. Validate configuration
2. Create cluster: `pcluster create-cluster`
3. Wait for cluster to be ready

### Post-Deployment Setup (20 minutes)
1. SSH to head node
2. Run setup scripts
3. Configure database connection
4. Initialize database schema
5. Start prediction API and job optimizer services

### Testing (10 minutes)
1. Test SLURM: `sinfo`, `squeue`
2. Submit test job
3. Verify monitoring works
4. Test prediction API

**Total Time**: ~1.5 hours

## 💰 Cost Breakdown

### Fixed Costs (Always Running)
| Resource | Instance | Cost/Hour | Cost/Month |
|----------|----------|-----------|------------|
| Head Node | c5.xlarge | $0.17 | $122 |
| Database | db.t3.small | $0.034 | $25 |
| Storage | EFS 500GB | - | $150 |
| **Total Fixed** | | | **$297** |

### Variable Costs (Compute Nodes)
| Usage | Nodes | Hours/Day | Days/Month | Cost/Month |
|-------|-------|-----------|------------|------------|
| Minimal | 2 | 8 | 20 | $218 |
| Moderate | 5 | 8 | 20 | $544 |
| Heavy | 10 | 8 | 20 | $1,088 |

### Total Monthly Cost
- **Minimal**: $515/month (2 nodes, 8 hrs/day)
- **Moderate**: $841/month (5 nodes, 8 hrs/day)
- **Heavy**: $1,385/month (10 nodes, 8 hrs/day)

### Cost Optimization
- **Spot Instances**: 50-70% savings on compute
- **Auto-scaling**: Nodes terminate when idle (10 min)
- **Scheduled shutdown**: Stop cluster nights/weekends

## 📋 Before You Deploy - Checklist

### AWS Account Setup
- [ ] AWS account with admin or appropriate IAM permissions
- [ ] AWS CLI installed: `aws --version`
- [ ] AWS credentials configured: `aws configure`
- [ ] Default region set (e.g., us-east-1)

### Network Configuration
- [ ] VPC created or identified
- [ ] Public subnet with internet gateway (for head node)
- [ ] Private subnet (for compute nodes)
- [ ] Security groups configured:
  - SSH (port 22) from your IP
  - PostgreSQL (port 5432) within VPC
  - HTTP (port 8000) for prediction API

### EC2 Key Pair
- [ ] Key pair created in your region
- [ ] Private key downloaded and secured
- [ ] Key pair name noted for configuration

### S3 Bucket
- [ ] Bucket name chosen (must be globally unique)
- [ ] Bucket created: `aws s3 mb s3://your-bucket-name`
- [ ] Setup scripts uploaded

### Budget & Limits
- [ ] AWS budget set up (recommended: $500-1,500/month)
- [ ] EC2 instance limits checked (need 10+ c5.4xlarge)
- [ ] Billing alerts configured

## 🎯 Phase 2 Goals

### Data Collection (Week 1-2)
- Deploy cluster and validate setup
- Run 50-100 OpenROAD jobs with variations
- Collect real execution metrics via SPANK plugin
- Validate stage detection accuracy > 95%

### Model Training (Week 2)
- Import production data to PostgreSQL
- Retrain models on real OpenROAD data
- Achieve R² > 0.85 on test set
- Deploy updated models to prediction API

### Dynamic Optimization (Week 3)
- Enable job optimizer service
- Submit 20-30 optimized jobs
- Compare baseline vs optimized efficiency
- Validate predictions within 20% of actual

### Success Metrics
- ✓ 50+ jobs collected with real OpenROAD data
- ✓ Model accuracy R² > 0.85 on test set
- ✓ Efficiency improvement > 15% vs baseline
- ✓ No job failures due to under-allocation
- ✓ Prediction latency < 100ms

## ⚠️ Important Notes

### Security
- **Never commit credentials** to git
- Use AWS Secrets Manager for sensitive data
- Restrict security groups to minimum required access
- Enable encryption for EFS and RDS

### Data Privacy
- All log processing happens on compute nodes (local)
- No external transmission of proprietary design data
- Metrics stored in private VPC
- Comply with data residency requirements

### Monitoring
- CloudWatch logs enabled for troubleshooting
- SLURM accounting tracks all jobs
- Prediction API logs all requests
- Set up billing alerts

## 🔄 Rollback Plan

If deployment fails or issues arise:

1. **Stop compute fleet** (saves money):
   ```bash
   pcluster update-compute-fleet --cluster-name hpc-optimization --status STOP_REQUESTED
   ```

2. **Debug on head node**:
   - Check logs: `/var/log/parallelcluster/`
   - Test services: `systemctl status prediction-api`
   - Verify database: `psql -h ENDPOINT -U admin -d hpc_metrics`

3. **Delete and recreate** if needed:
   ```bash
   pcluster delete-cluster --cluster-name hpc-optimization
   # Fix configuration
   pcluster create-cluster --cluster-name hpc-optimization --cluster-configuration aws/cluster-config.yaml
   ```

4. **Fallback to local**:
   - Continue Phase 1 with more local data collection
   - Fix issues before redeploying

## 📚 Next Steps

### Immediate (Before Deployment)
1. Review `aws/DEPLOYMENT_GUIDE.md` thoroughly
2. Complete the "Before You Deploy" checklist above
3. Update `aws/cluster-config.yaml` with your AWS IDs
4. Test AWS CLI access: `aws ec2 describe-instances`

### After Deployment
1. Follow deployment guide step-by-step
2. Validate cluster is working: `sinfo`, `sbatch test_job.sh`
3. Start with Task 16: Deploy PostgreSQL database
4. Continue with Tasks 17-37 for full Phase 2

### Support Resources
- AWS ParallelCluster Docs: https://docs.aws.amazon.com/parallelcluster/
- SLURM Documentation: https://slurm.schedmd.com/documentation.html
- Project spec: `.kiro/specs/hpc-resource-optimization/`

---

## Ready to Deploy? 🚀

You have everything needed to deploy Phase 2:
- ✅ Cluster configuration
- ✅ Setup scripts
- ✅ Deployment guide
- ✅ Cost estimates
- ✅ Rollback plan

**Estimated deployment time**: 1.5 hours
**Estimated monthly cost**: $515-1,385 (depending on usage)

When ready, start with: `aws/DEPLOYMENT_GUIDE.md`
