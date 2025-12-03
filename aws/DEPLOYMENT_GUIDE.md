# AWS Parallel Cluster Deployment Guide

## Prerequisites

1. **AWS Account** with appropriate permissions
2. **AWS CLI** installed and configured
3. **AWS ParallelCluster CLI** installed
4. **EC2 Key Pair** created in your region
5. **VPC and Subnet** configured

## Step 1: Install AWS ParallelCluster CLI

```bash
pip3 install aws-parallelcluster
pcluster version
```

## Step 2: Configure AWS Credentials

```bash
aws configure
# Enter your AWS Access Key ID
# Enter your AWS Secret Access Key
# Enter your default region (e.g., us-east-1)
```

## Step 3: Create S3 Bucket for Scripts

```bash
# Create bucket
aws s3 mb s3://hpc-optimization-scripts-YOUR-ACCOUNT-ID

# Upload setup scripts
aws s3 cp aws/scripts/setup-compute-node.sh s3://hpc-optimization-scripts-YOUR-ACCOUNT-ID/scripts/
aws s3 cp aws/scripts/setup-head-node.sh s3://hpc-optimization-scripts-YOUR-ACCOUNT-ID/scripts/

# Make scripts public (or use IAM roles)
aws s3api put-object-acl --bucket hpc-optimization-scripts-YOUR-ACCOUNT-ID \
    --key scripts/setup-compute-node.sh --acl public-read
```

## Step 4: Update Cluster Configuration

Edit `aws/cluster-config.yaml`:

1. **Replace subnet IDs**:
   ```yaml
   SubnetId: subnet-XXXXXXXX  # Your actual subnet ID
   ```

2. **Replace key pair name**:
   ```yaml
   KeyName: your-key-pair  # Your EC2 key pair name
   ```

3. **Replace S3 bucket**:
   ```yaml
   Script: s3://hpc-optimization-scripts-YOUR-ACCOUNT-ID/scripts/setup-compute-node.sh
   ```

4. **Get your subnet ID**:
   ```bash
   aws ec2 describe-subnets --query 'Subnets[*].[SubnetId,VpcId,AvailabilityZone]' --output table
   ```

## Step 5: Create RDS PostgreSQL Database

```bash
# Create DB subnet group
aws rds create-db-subnet-group \
    --db-subnet-group-name hpc-metrics-subnet-group \
    --db-subnet-group-description "Subnet group for HPC metrics DB" \
    --subnet-ids subnet-XXXXXXXX subnet-YYYYYYYY

# Create PostgreSQL instance
aws rds create-db-instance \
    --db-instance-identifier hpc-metrics-db \
    --db-instance-class db.t3.small \
    --engine postgres \
    --engine-version 15.3 \
    --master-username admin \
    --master-user-password YOUR-SECURE-PASSWORD \
    --allocated-storage 100 \
    --db-subnet-group-name hpc-metrics-subnet-group \
    --vpc-security-group-ids sg-XXXXXXXX \
    --backup-retention-period 7 \
    --preferred-backup-window "03:00-04:00" \
    --preferred-maintenance-window "mon:04:00-mon:05:00" \
    --tags Key=Project,Value=HPC-Resource-Optimization

# Wait for DB to be available (takes 5-10 minutes)
aws rds wait db-instance-available --db-instance-identifier hpc-metrics-db

# Get DB endpoint
aws rds describe-db-instances \
    --db-instance-identifier hpc-metrics-db \
    --query 'DBInstances[0].Endpoint.Address' \
    --output text
```

## Step 6: Create Cluster

```bash
# Validate configuration
pcluster create-cluster --cluster-name hpc-optimization \
    --cluster-configuration aws/cluster-config.yaml \
    --dryrun

# Create cluster (takes 10-15 minutes)
pcluster create-cluster --cluster-name hpc-optimization \
    --cluster-configuration aws/cluster-config.yaml

# Monitor creation
pcluster describe-cluster --cluster-name hpc-optimization
```

## Step 7: Connect to Head Node

```bash
# Get head node IP
pcluster ssh --cluster-name hpc-optimization -i ~/.ssh/your-key-pair.pem

# Or use SSM (no key needed)
pcluster ssh --cluster-name hpc-optimization
```

## Step 8: Setup Head Node

```bash
# On head node
cd /home/ubuntu

# Download setup script
wget https://s3.amazonaws.com/hpc-optimization-scripts-YOUR-ACCOUNT-ID/scripts/setup-head-node.sh
chmod +x setup-head-node.sh

# Run setup
./setup-head-node.sh

# Copy project files
cd /shared/hpc-optimization
# Upload your project files here (scp or git clone)
```

## Step 9: Configure Database Connection

```bash
# Edit .env file
nano /shared/hpc-optimization/.env

# Update with your RDS endpoint
DB_HOST=hpc-metrics-db.XXXXXXXXXX.us-east-1.rds.amazonaws.com
DB_PORT=5432
DB_NAME=hpc_metrics
DB_USER=admin
DB_PASSWORD=YOUR-SECURE-PASSWORD
```

## Step 10: Initialize Database

```bash
cd /shared/hpc-optimization

# Initialize schema
python3 database/schema.py

# Verify connection
python3 -c "
from database.schema import init_database, get_session
engine = init_database('postgresql://admin:PASSWORD@ENDPOINT:5432/hpc_metrics')
print('Database connection successful!')
"
```

## Step 11: Start Services

```bash
# Start prediction API
sudo systemctl start prediction-api
sudo systemctl status prediction-api

# Start job optimizer
sudo systemctl start job-optimizer
sudo systemctl status job-optimizer

# Enable on boot
sudo systemctl enable prediction-api
sudo systemctl enable job-optimizer
```

## Step 12: Test Cluster

```bash
# Test SLURM
sinfo
squeue

# Submit test job
cat > test_job.sh <<EOF
#!/bin/bash
#SBATCH --job-name=test
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --time=00:05:00
#SBATCH --output=test_%j.out

echo "Hello from compute node!"
hostname
date
EOF

sbatch test_job.sh

# Check job status
squeue
sacct
```

## Step 13: Deploy SPANK Plugin (Optional - Phase 5)

```bash
# Compile SPANK plugin on head node
cd /shared/hpc-optimization/spank
gcc -shared -fPIC -o spank_monitor.so spank_monitor.c -lslurm

# Copy to shared location
cp spank_monitor.so /shared/spank/

# Compute nodes will pick it up on next launch
```

## Cost Estimation

### Always Running
- Head node (c5.xlarge): ~$0.17/hour = ~$122/month
- RDS PostgreSQL (db.t3.small): ~$0.034/hour = ~$25/month
- EFS storage (500GB): ~$150/month
- **Total fixed**: ~$297/month

### Variable (Compute Nodes)
- c5.4xlarge: ~$0.68/hour per node
- 2 nodes × 8 hours/day × 20 days = ~$218/month
- 10 nodes × 8 hours/day × 20 days = ~$1,088/month

### Total Monthly Cost
- **Minimal usage**: ~$515/month
- **Moderate usage**: ~$850/month
- **Heavy usage**: ~$1,385/month

## Cost Optimization

1. **Use Spot Instances** (50-70% savings):
   ```yaml
   ComputeResources:
     - Name: openroad-nodes
       InstanceType: c5.4xlarge
       MinCount: 0
       MaxCount: 10
       SpotPrice: 0.30  # Set max spot price
   ```

2. **Auto-scaling**: Nodes automatically terminate when idle (10 min default)

3. **Scheduled Shutdown**: Stop cluster nights/weekends if not needed
   ```bash
   pcluster update-compute-fleet --cluster-name hpc-optimization --status STOP_REQUESTED
   ```

## Monitoring

### CloudWatch Logs
```bash
# View logs
aws logs tail /aws/parallelcluster/hpc-optimization --follow
```

### SLURM Accounting
```bash
# View job history
sacct -S 2025-11-01
sacct --format=JobID,JobName,Partition,State,Elapsed,MaxRSS,CPUTime
```

### Prediction API
```bash
# Test API
curl http://localhost:8000/health
curl -X POST http://localhost:8000/predict -H "Content-Type: application/json" -d '{
  "cell_count": 50000,
  "net_count": 45000,
  "die_area_um2": 10000000,
  "utilization_target": 0.7,
  "clock_freq_mhz": 500,
  "technology_node_nm": 130
}'
```

## Troubleshooting

### Cluster Creation Fails
```bash
# Check logs
pcluster get-cluster-log-events --cluster-name hpc-optimization

# Delete and recreate
pcluster delete-cluster --cluster-name hpc-optimization
```

### Compute Nodes Not Starting
```bash
# Check queue status
sinfo -l

# Check SLURM logs
sudo tail -f /var/log/slurmctld.log
```

### Database Connection Issues
```bash
# Test connection
psql -h ENDPOINT -U admin -d hpc_metrics

# Check security group allows port 5432 from cluster
```

## Cleanup

```bash
# Stop compute fleet
pcluster update-compute-fleet --cluster-name hpc-optimization --status STOP_REQUESTED

# Delete cluster
pcluster delete-cluster --cluster-name hpc-optimization

# Delete RDS instance
aws rds delete-db-instance --db-instance-identifier hpc-metrics-db --skip-final-snapshot

# Delete S3 bucket
aws s3 rb s3://hpc-optimization-scripts-YOUR-ACCOUNT-ID --force
```

## Next Steps

After deployment:
1. Run baseline jobs (Task 25)
2. Collect 50-100 job metrics
3. Retrain model on production data (Task 26)
4. Deploy prediction API (Task 27)
5. Enable dynamic optimization (Tasks 28-30)
