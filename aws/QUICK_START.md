# Quick Start Guide - AWS Deployment

## Current Status ✓

**Phase 1 Complete:**
- ✅ Local development environment working
- ✅ Database schema and monitoring implemented
- ✅ 7 test jobs collected
- ✅ Ridge regression models trained
- ✅ Memory prediction: R² = 0.95 (excellent!)

**Phase 2 Ready:**
- ✅ Cluster configuration created
- ✅ Setup scripts prepared
- ✅ Deployment guide written
- ⚠️ AWS credentials need configuration

## Next Steps (30 minutes)

### Step 1: Configure AWS Credentials (5 min)

You need an AWS account with appropriate permissions. If you don't have one:

**Option A: Use Existing AWS Account**
```bash
# Configure AWS CLI with your credentials
aws configure

# You'll be prompted for:
# - AWS Access Key ID: [Your access key]
# - AWS Secret Access Key: [Your secret key]
# - Default region: us-east-1 (or your preferred region)
# - Default output format: json
```

**Option B: Create New AWS Account**
1. Go to https://aws.amazon.com/
2. Click "Create an AWS Account"
3. Follow signup process (requires credit card)
4. Create IAM user with admin permissions
5. Generate access keys
6. Run `aws configure` with those keys

**Option C: Use AWS SSO/IAM Identity Center**
```bash
aws configure sso
# Follow prompts to authenticate
```

### Step 2: Run Pre-Deployment Check (2 min)

```bash
./aws/pre-deployment-check.sh
```

This will verify:
- ✓ AWS CLI installed
- ✓ Credentials configured
- ✓ ParallelCluster CLI installed
- ✓ EC2 key pairs exist
- ✓ VPC and subnets available
- ✓ Project files present

### Step 3: Install ParallelCluster CLI (2 min)

If not already installed:
```bash
pip3 install aws-parallelcluster
pcluster version
```

### Step 4: Create EC2 Key Pair (2 min)

```bash
# Create key pair
aws ec2 create-key-pair \
    --key-name hpc-optimization-key \
    --query 'KeyMaterial' \
    --output text > ~/.ssh/hpc-optimization-key.pem

# Set permissions
chmod 400 ~/.ssh/hpc-optimization-key.pem

# Verify
aws ec2 describe-key-pairs --key-names hpc-optimization-key
```

### Step 5: Get VPC and Subnet IDs (2 min)

```bash
# List VPCs
aws ec2 describe-vpcs --query 'Vpcs[*].[VpcId,CidrBlock,IsDefault]' --output table

# List subnets (replace vpc-XXXXX with your VPC ID)
aws ec2 describe-subnets \
    --filters "Name=vpc-id,Values=vpc-XXXXX" \
    --query 'Subnets[*].[SubnetId,AvailabilityZone,CidrBlock]' \
    --output table

# Note down:
# - One public subnet ID (for head node)
# - One private subnet ID (for compute nodes, or use same as public)
```

### Step 6: Update Cluster Configuration (5 min)

Edit `aws/cluster-config.yaml`:

```yaml
# Line 5: Update subnet for head node
HeadNode:
  Networking:
    SubnetId: subnet-YOUR-ACTUAL-SUBNET-ID  # Replace this

# Line 8: Update key pair name
  Ssh:
    KeyName: hpc-optimization-key  # Or your key name

# Line 30: Update subnet for compute nodes
      Networking:
        SubnetIds:
          - subnet-YOUR-ACTUAL-SUBNET-ID  # Replace this

# Line 35: Update S3 bucket (will create in next step)
      CustomActions:
        OnNodeConfigured:
          Script: s3://hpc-optimization-YOUR-ACCOUNT-ID/scripts/setup-compute-node.sh
```

### Step 7: Create S3 Bucket and Upload Scripts (5 min)

```bash
# Get your AWS account ID
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
echo "Your Account ID: $ACCOUNT_ID"

# Create S3 bucket (must be globally unique)
aws s3 mb s3://hpc-optimization-$ACCOUNT_ID

# Upload setup scripts
aws s3 cp aws/scripts/setup-compute-node.sh s3://hpc-optimization-$ACCOUNT_ID/scripts/
aws s3 cp aws/scripts/setup-head-node.sh s3://hpc-optimization-$ACCOUNT_ID/scripts/

# Verify
aws s3 ls s3://hpc-optimization-$ACCOUNT_ID/scripts/
```

### Step 8: Validate Configuration (2 min)

```bash
# Validate cluster config (dry run)
pcluster create-cluster \
    --cluster-name hpc-optimization \
    --cluster-configuration aws/cluster-config.yaml \
    --dryrun

# If validation passes, you'll see: "Request would have succeeded, but DryRun flag is set."
```

### Step 9: Deploy Cluster (15 min wait)

```bash
# Create cluster
pcluster create-cluster \
    --cluster-name hpc-optimization \
    --cluster-configuration aws/cluster-config.yaml

# Monitor progress (takes 10-15 minutes)
watch -n 30 'pcluster describe-cluster --cluster-name hpc-optimization --query "clusterStatus" --output text'

# Or check in AWS Console: CloudFormation > Stacks
```

### Step 10: Connect and Setup (10 min)

```bash
# SSH to head node
pcluster ssh --cluster-name hpc-optimization -i ~/.ssh/hpc-optimization-key.pem

# On head node, run setup
cd /home/ubuntu
wget https://s3.amazonaws.com/hpc-optimization-$ACCOUNT_ID/scripts/setup-head-node.sh
chmod +x setup-head-node.sh
./setup-head-node.sh

# Copy project files
# (You'll need to scp or git clone your project)
```

## Cost Estimate

**During deployment (15 min)**: ~$0.05
**After deployment (idle)**: ~$0.20/hour = ~$144/day if left running

**Important**: Remember to stop or delete the cluster when not in use!

```bash
# Stop compute fleet (keeps head node running)
pcluster update-compute-fleet --cluster-name hpc-optimization --status STOP_REQUESTED

# Delete entire cluster
pcluster delete-cluster --cluster-name hpc-optimization
```

## Troubleshooting

### "No default VPC found"
```bash
# Create default VPC
aws ec2 create-default-vpc
```

### "Insufficient capacity"
- Try different region: `aws configure set region us-west-2`
- Or use different instance type in cluster-config.yaml

### "Access Denied"
- Check IAM permissions
- Need: EC2, S3, CloudFormation, IAM permissions

### "Cluster creation failed"
```bash
# Check logs
pcluster get-cluster-log-events --cluster-name hpc-optimization

# Delete and retry
pcluster delete-cluster --cluster-name hpc-optimization
```

## What's Next?

After successful deployment:

1. **Test cluster**: `sinfo`, `sbatch test_job.sh`
2. **Setup database**: Create RDS PostgreSQL (see DEPLOYMENT_GUIDE.md Step 5)
3. **Run baseline jobs**: Collect 50-100 OpenROAD jobs
4. **Retrain model**: On real production data
5. **Enable optimization**: Deploy prediction API and job optimizer

## Need Help?

- Full guide: `aws/DEPLOYMENT_GUIDE.md`
- AWS ParallelCluster docs: https://docs.aws.amazon.com/parallelcluster/
- Troubleshooting: See DEPLOYMENT_GUIDE.md "Troubleshooting" section

## Summary

**Time to deploy**: ~30 minutes (mostly waiting for cluster creation)
**Cost**: ~$0.20/hour when idle, $0.68/hour per active compute node
**Next milestone**: Collect 50-100 real OpenROAD jobs for model training

Ready? Start with Step 1: Configure AWS credentials! 🚀
