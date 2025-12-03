#!/bin/bash
# Complete AWS ParallelCluster Deployment Script
# HPC Resource Optimization with Singularity

set -e

echo "=========================================="
echo "AWS ParallelCluster Deployment"
echo "HPC Resource Optimization System"
echo "=========================================="
echo ""

# Configuration
CLUSTER_NAME="hpc-optimization"
REGION="us-east-1"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
BUCKET_NAME="hpc-optimization-${ACCOUNT_ID}"
KEY_NAME="eda-cluster-key"
VPC_ID="vpc-0b30951358f00a943"  # Default VPC
SUBNET_ID="subnet-06b3a8f511e1f1213"  # us-east-1a

echo "Configuration:"
echo "  Cluster Name: $CLUSTER_NAME"
echo "  Region: $REGION"
echo "  Account ID: $ACCOUNT_ID"
echo "  S3 Bucket: $BUCKET_NAME"
echo "  VPC: $VPC_ID"
echo "  Subnet: $SUBNET_ID"
echo "  Key Pair: $KEY_NAME"
echo ""

# Step 1: Create S3 bucket
echo "Step 1: Creating S3 bucket..."
if aws s3 ls "s3://$BUCKET_NAME" 2>/dev/null; then
    echo "✓ S3 bucket already exists: $BUCKET_NAME"
else
    aws s3 mb "s3://$BUCKET_NAME" --region $REGION
    echo "✓ Created S3 bucket: $BUCKET_NAME"
fi
echo ""

# Step 2: Package and upload project files
echo "Step 2: Packaging project files..."
tar -czf /tmp/hpc-optimization.tar.gz \
    --exclude='*.pyc' \
    --exclude='__pycache__' \
    --exclude='.git' \
    --exclude='data/metrics/*' \
    --exclude='aws-eda-samples' \
    database/ monitoring/ prediction/ scripts/ \
    requirements.txt

aws s3 cp /tmp/hpc-optimization.tar.gz "s3://$BUCKET_NAME/"
echo "✓ Uploaded project files"
echo ""

# Step 3: Upload deployment scripts
echo "Step 3: Uploading deployment scripts..."
aws s3 cp aws/scripts/ "s3://$BUCKET_NAME/scripts/" --recursive
echo "✓ Uploaded deployment scripts"
echo ""

# Step 4: Compile and upload SPANK plugin
echo "Step 4: Compiling SPANK plugin..."
if [ -f "spank/spank_monitor.c" ]; then
    cd spank
    if [ ! -f "spank_monitor.so" ]; then
        echo "Compiling SPANK plugin..."
        gcc -shared -fPIC -o spank_monitor.so spank_monitor.c -lpthread || {
            echo "⚠ SPANK plugin compilation failed (will compile on cluster)"
        }
    fi
    if [ -f "spank_monitor.so" ]; then
        aws s3 cp spank_monitor.so "s3://$BUCKET_NAME/spank/"
        echo "✓ Uploaded SPANK plugin"
    fi
    cd ..
else
    echo "⚠ SPANK plugin source not found"
fi
echo ""

# Step 5: Create updated cluster configuration
echo "Step 5: Creating cluster configuration..."
cat > aws/cluster-config-final.yaml <<EOF
Region: $REGION
Image:
  Os: alinux2

HeadNode:
  InstanceType: c5.xlarge
  Networking:
    SubnetId: $SUBNET_ID
  Ssh:
    KeyName: $KEY_NAME
  LocalStorage:
    RootVolume:
      Size: 50
  Iam:
    AdditionalIamPolicies:
      - Policy: arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore
      - Policy: arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy
      - Policy: arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess
  CustomActions:
    OnNodeConfigured:
      Script: s3://$BUCKET_NAME/scripts/setup-head-node.sh

Scheduling:
  Scheduler: slurm
  SlurmQueues:
    - Name: compute
      ComputeResources:
        - Name: openroad
          InstanceType: c5.4xlarge
          MinCount: 0
          MaxCount: 4
      Networking:
        SubnetIds:
          - $SUBNET_ID
      ComputeSettings:
        LocalStorage:
          RootVolume:
            Size: 50
      CustomActions:
        OnNodeConfigured:
          Script: s3://$BUCKET_NAME/scripts/setup-compute-node.sh
  SlurmSettings:
    ScaledownIdletime: 5
    EnableMemoryBasedScheduling: true

SharedStorage:
  - MountDir: /shared
    Name: shared-efs
    StorageType: Efs
    EfsSettings:
      ThroughputMode: bursting
      PerformanceMode: generalPurpose
      Encrypted: true

Monitoring:
  DetailedMonitoring: true
  Logs:
    CloudWatch:
      Enabled: true
      RetentionInDays: 7

Tags:
  - Key: Project
    Value: HPC-Resource-Optimization
  - Key: Environment
    Value: Development
EOF

echo "✓ Created cluster configuration"
echo ""

# Step 6: Create setup scripts
echo "Step 6: Creating setup scripts..."

# Head node setup script
cat > /tmp/setup-head-node.sh <<'HEADEOF'
#!/bin/bash
set -e
echo "=== Setting up head node ==="

# Install Singularity
echo "Installing Singularity..."
sudo yum install -y epel-release
sudo yum install -y singularity-ce

# Download project files
echo "Downloading project files..."
aws s3 cp s3://BUCKET_NAME/hpc-optimization.tar.gz /tmp/
cd /shared
sudo tar -xzf /tmp/hpc-optimization.tar.gz

# Install Python dependencies
echo "Installing Python dependencies..."
sudo yum install -y python3-pip
sudo pip3 install -r /shared/requirements.txt

# Create directories
sudo mkdir -p /shared/containers /shared/logs /shared/metrics /shared/designs /shared/spank

# Download SPANK plugin
aws s3 cp s3://BUCKET_NAME/spank/spank_monitor.so /shared/spank/ || echo "SPANK plugin not found"

# Convert OpenROAD Docker image to Singularity
echo "Converting OpenROAD container..."
cd /shared/containers
singularity pull openroad.sif docker://openroad/flow-ubuntu:latest || echo "Container pull failed"

echo "✓ Head node setup complete"
HEADEOF

sed "s|BUCKET_NAME|$BUCKET_NAME|g" /tmp/setup-head-node.sh > /tmp/setup-head-node-final.sh
aws s3 cp /tmp/setup-head-node-final.sh "s3://$BUCKET_NAME/scripts/setup-head-node.sh"

# Compute node setup script
cat > /tmp/setup-compute-node.sh <<'COMPUTEEOF'
#!/bin/bash
set -e
echo "=== Setting up compute node ==="

# Install Singularity
echo "Installing Singularity..."
sudo yum install -y epel-release
sudo yum install -y singularity-ce

# Verify Singularity
singularity --version

# Copy SPANK plugin if available
if [ -f "/shared/spank/spank_monitor.so" ]; then
    echo "Installing SPANK plugin..."
    sudo cp /shared/spank/spank_monitor.so /usr/lib64/slurm/
    echo "required /usr/lib64/slurm/spank_monitor.so" | sudo tee /opt/slurm/etc/plugstack.conf
    sudo systemctl restart slurmd
    echo "✓ SPANK plugin installed"
else
    echo "⚠ SPANK plugin not found, skipping"
fi

echo "✓ Compute node setup complete"
COMPUTEEOF

aws s3 cp /tmp/setup-compute-node.sh "s3://$BUCKET_NAME/scripts/setup-compute-node.sh"

echo "✓ Uploaded setup scripts"
echo ""

# Step 7: Validate configuration
echo "Step 7: Validating cluster configuration..."
pcluster create-cluster \
    --cluster-name $CLUSTER_NAME \
    --cluster-configuration aws/cluster-config-final.yaml \
    --region $REGION \
    --dryrun true 2>&1 | grep -q "DryRun flag is set" && {
    echo "✓ Configuration validated"
} || {
    echo "❌ Configuration validation failed"
    exit 1
}
echo ""

# Step 8: Create cluster
echo "Step 8: Creating ParallelCluster..."
echo "This will take 15-20 minutes..."
echo ""

read -p "Proceed with cluster creation? (yes/no): " CONFIRM
if [ "$CONFIRM" != "yes" ]; then
    echo "Deployment cancelled"
    exit 0
fi

pcluster create-cluster \
    --cluster-name $CLUSTER_NAME \
    --cluster-configuration aws/cluster-config-final.yaml \
    --region $REGION

echo ""
echo "=========================================="
echo "Cluster creation started!"
echo "=========================================="
echo ""
echo "Monitor progress:"
echo "  pcluster describe-cluster --cluster-name $CLUSTER_NAME --region $REGION"
echo ""
echo "Check status:"
echo "  watch -n 10 'pcluster describe-cluster --cluster-name $CLUSTER_NAME --region $REGION'"
echo ""
echo "SSH when ready:"
echo "  pcluster ssh --cluster-name $CLUSTER_NAME -i ~/.ssh/$KEY_NAME.pem --region $REGION"
echo ""
echo "Delete cluster:"
echo "  pcluster delete-cluster --cluster-name $CLUSTER_NAME --region $REGION"
echo ""
echo "Estimated time: 15-20 minutes"
echo "Estimated cost: ~$0.20/hour (head node only when idle)"
echo ""
