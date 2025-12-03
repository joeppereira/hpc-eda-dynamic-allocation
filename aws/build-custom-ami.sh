#!/bin/bash
# Build Custom AMI with Everything Pre-installed
# OpenROAD, Singularity, SPANK Plugin, ML Tools, etc.

set -e

echo "=========================================="
echo "Build Custom ParallelCluster AMI"
echo "Complete HPC Resource Optimization Stack"
echo "=========================================="
echo ""

# Configuration
REGION="us-east-1"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
BUCKET_NAME="hpc-optimization-${ACCOUNT_ID}"
KEY_NAME="eda-cluster-key"
SUBNET_ID="subnet-06b3a8f511e1f1213"
INSTANCE_TYPE="c5.2xlarge"  # 8 vCPU, 16GB RAM for building
AMI_NAME="parallelcluster-hpc-optimization-$(date +%Y%m%d-%H%M%S)"

echo "Configuration:"
echo "  Region: $REGION"
echo "  Account: $ACCOUNT_ID"
echo "  AMI Name: $AMI_NAME"
echo "  Instance Type: $INSTANCE_TYPE"
echo ""

# Step 1: Get base ParallelCluster AMI
echo "Step 1: Finding base ParallelCluster AMI..."
BASE_AMI=$(pcluster list-official-images \
    --region $REGION \
    --os alinux2 \
    --architecture x86_64 \
    --query 'images[0].amiId' \
    --output text)

echo "✓ Base AMI: $BASE_AMI"
echo ""

# Step 2: Upload build resources to S3
echo "Step 2: Uploading build resources to S3..."

# Package project files
tar -czf /tmp/hpc-optimization.tar.gz \
    --exclude='*.pyc' \
    --exclude='__pycache__' \
    --exclude='.git' \
    --exclude='data/metrics/*' \
    --exclude='aws-eda-samples' \
    database/ monitoring/ prediction/ scripts/ spank/ \
    requirements.txt

aws s3 cp /tmp/hpc-optimization.tar.gz "s3://$BUCKET_NAME/"
echo "✓ Uploaded project files"
echo ""

# Step 3: Create comprehensive setup script
echo "Step 3: Creating AMI setup script..."

cat > /tmp/ami-setup.sh <<'SETUPSCRIPT'
#!/bin/bash
set -e

echo "=== Custom AMI Setup Script ==="
echo "Installing: Singularity, OpenROAD, SPANK, ML Tools"
echo ""

# Update system
echo "[1/8] Updating system..."
sudo yum update -y

# Install Singularity
echo "[2/8] Installing Singularity..."
sudo yum install -y epel-release
sudo yum install -y singularity-ce
singularity --version

# Install development tools for SPANK plugin
echo "[3/8] Installing SLURM development tools..."
sudo yum install -y \
    gcc gcc-c++ make \
    slurm slurm-devel \
    git wget curl

# Install Python and ML dependencies
echo "[4/8] Installing Python and ML tools..."
sudo yum install -y python3 python3-pip python3-devel
sudo pip3 install --upgrade pip

sudo pip3 install \
    numpy==1.24.3 \
    pandas==2.0.3 \
    scikit-learn==1.3.0 \
    psutil==5.9.5 \
    sqlalchemy==2.0.19 \
    psycopg2-binary==2.9.7 \
    fastapi==0.103.1 \
    uvicorn==0.23.2 \
    pydantic==2.3.0 \
    matplotlib==3.7.2 \
    seaborn==0.12.2 \
    pyyaml==6.0.1 \
    python-dotenv==1.0.0

# Install Fluent Bit for log processing
echo "[5/8] Installing Fluent Bit..."
sudo yum install -y fluent-bit

# Download and extract project files
echo "[6/8] Downloading project files..."
sudo mkdir -p /opt/hpc-optimization
cd /opt/hpc-optimization
aws s3 cp s3://BUCKET_NAME/hpc-optimization.tar.gz .
sudo tar -xzf hpc-optimization.tar.gz
sudo rm hpc-optimization.tar.gz

# Compile SPANK plugin
echo "[7/8] Compiling SPANK plugin..."
cd /opt/hpc-optimization/spank
sudo gcc -shared -fPIC -o spank_monitor.so spank_monitor.c -lpthread
sudo mkdir -p /opt/spank
sudo cp spank_monitor.so /opt/spank/
echo "✓ SPANK plugin compiled and installed"

# Convert OpenROAD Docker image to Singularity
echo "[8/8] Converting OpenROAD container..."
sudo mkdir -p /opt/containers
cd /opt/containers
sudo singularity pull openroad.sif docker://openroad/flow-ubuntu:latest
sudo chmod 644 openroad.sif
echo "✓ OpenROAD container ready"

# Create helper scripts
echo "Creating helper scripts..."
sudo mkdir -p /opt/hpc-optimization/bin

# Script to setup shared storage
cat > /tmp/setup-shared.sh <<'SHARED'
#!/bin/bash
# Run this on first boot to setup shared storage
set -e

echo "Setting up shared storage..."

# Copy containers to shared storage
sudo mkdir -p /shared/containers
sudo cp /opt/containers/openroad.sif /shared/containers/

# Copy SPANK plugin
sudo mkdir -p /shared/spank
sudo cp /opt/spank/spank_monitor.so /shared/spank/

# Copy project files
sudo mkdir -p /shared/hpc-optimization
sudo cp -r /opt/hpc-optimization/* /shared/hpc-optimization/

# Create directories
sudo mkdir -p /shared/{logs,metrics,designs,config}

echo "✓ Shared storage setup complete"
SHARED

sudo mv /tmp/setup-shared.sh /opt/hpc-optimization/bin/
sudo chmod +x /opt/hpc-optimization/bin/setup-shared.sh

# Verify installations
echo ""
echo "=== Verification ==="
echo "Singularity: $(singularity --version)"
echo "Python: $(python3 --version)"
echo "SPANK plugin: $(ls -lh /opt/spank/spank_monitor.so)"
echo "OpenROAD container: $(ls -lh /opt/containers/openroad.sif)"
echo "Project files: $(du -sh /opt/hpc-optimization)"
echo ""

# Clean up
echo "Cleaning up..."
sudo yum clean all
sudo rm -rf /tmp/*
sudo rm -rf /var/cache/yum

echo "✓ AMI setup complete!"
SETUPSCRIPT

# Replace bucket name
sed "s|BUCKET_NAME|$BUCKET_NAME|g" /tmp/ami-setup.sh > /tmp/ami-setup-final.sh

# Upload setup script
aws s3 cp /tmp/ami-setup-final.sh "s3://$BUCKET_NAME/scripts/ami-setup.sh"
echo "✓ Setup script uploaded"
echo ""

# Step 4: Launch build instance
echo "Step 4: Launching build instance..."

# Create security group
SG_ID=$(aws ec2 create-security-group \
    --group-name ami-builder-sg \
    --description "Security group for AMI builder" \
    --region $REGION \
    --output text 2>/dev/null || \
    aws ec2 describe-security-groups \
        --filters "Name=group-name,Values=ami-builder-sg" \
        --query 'SecurityGroups[0].GroupId' \
        --output text \
        --region $REGION)

# Allow SSH
aws ec2 authorize-security-group-ingress \
    --group-id $SG_ID \
    --protocol tcp \
    --port 22 \
    --cidr 0.0.0.0/0 \
    --region $REGION 2>/dev/null || echo "SSH rule exists"

# Launch instance
INSTANCE_ID=$(aws ec2 run-instances \
    --image-id $BASE_AMI \
    --instance-type $INSTANCE_TYPE \
    --key-name $KEY_NAME \
    --subnet-id $SUBNET_ID \
    --security-group-ids $SG_ID \
    --iam-instance-profile Name=ecsInstanceRole \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=ami-builder},{Key=Project,Value=HPC-Optimization}]" \
    --region $REGION \
    --query 'Instances[0].InstanceId' \
    --output text)

echo "✓ Launched instance: $INSTANCE_ID"
echo ""

# Step 5: Wait for instance
echo "Step 5: Waiting for instance to be ready..."
aws ec2 wait instance-running \
    --instance-ids $INSTANCE_ID \
    --region $REGION

PUBLIC_IP=$(aws ec2 describe-instances \
    --instance-ids $INSTANCE_ID \
    --query 'Reservations[0].Instances[0].PublicIpAddress' \
    --output text \
    --region $REGION)

echo "✓ Instance running at: $PUBLIC_IP"
echo "  Waiting 90 seconds for system initialization..."
sleep 90
echo ""

# Step 6: Run setup script
echo "Step 6: Running setup script on instance..."
echo "This will take 10-15 minutes (downloading and building)..."
echo ""

ssh -i ~/.ssh/$KEY_NAME.pem \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    ec2-user@$PUBLIC_IP \
    "aws s3 cp s3://$BUCKET_NAME/scripts/ami-setup.sh /tmp/ && chmod +x /tmp/ami-setup.sh && /tmp/ami-setup.sh"

echo ""
echo "✓ Setup complete!"
echo ""

# Step 7: Create AMI
echo "Step 7: Creating AMI..."
echo "Stopping instance..."
aws ec2 stop-instances \
    --instance-ids $INSTANCE_ID \
    --region $REGION

aws ec2 wait instance-stopped \
    --instance-ids $INSTANCE_ID \
    --region $REGION

echo "Creating AMI image..."
AMI_ID=$(aws ec2 create-image \
    --instance-id $INSTANCE_ID \
    --name "$AMI_NAME" \
    --description "ParallelCluster with OpenROAD, Singularity, SPANK plugin, ML tools" \
    --region $REGION \
    --query 'ImageId' \
    --output text)

echo "✓ AMI creation started: $AMI_ID"
echo "  Waiting for AMI to be available (5-10 minutes)..."

aws ec2 wait image-available \
    --image-ids $AMI_ID \
    --region $REGION

echo "✓ AMI ready: $AMI_ID"
echo ""

# Step 8: Cleanup
echo "Step 8: Cleaning up..."
aws ec2 terminate-instances \
    --instance-ids $INSTANCE_ID \
    --region $REGION

echo "✓ Build instance terminated"
echo ""

# Step 9: Save AMI ID
echo "Step 9: Saving AMI configuration..."
cat > aws/custom-ami-id.txt <<EOF
# Custom AMI for HPC Resource Optimization
# Created: $(date)
AMI_ID=$AMI_ID
REGION=$REGION
BASE_AMI=$BASE_AMI

# Use in cluster config:
# slurm:
#   ParallelClusterConfig:
#     ComputeNodeAmi: $AMI_ID
EOF

echo "✓ AMI ID saved to aws/custom-ami-id.txt"
echo ""

echo "=========================================="
echo "Custom AMI Build Complete!"
echo "=========================================="
echo ""
echo "AMI ID: $AMI_ID"
echo "Region: $REGION"
echo ""
echo "What's included:"
echo "  ✓ Singularity $(singularity --version 2>/dev/null || echo 'latest')"
echo "  ✓ OpenROAD container (pre-pulled)"
echo "  ✓ SPANK plugin (pre-compiled)"
echo "  ✓ Python ML tools (scikit-learn, pandas, etc.)"
echo "  ✓ Fluent Bit (log processing)"
echo "  ✓ Project files (/opt/hpc-optimization)"
echo ""
echo "Next steps:"
echo "  1. Update cluster config with AMI ID:"
echo "     ComputeNodeAmi: $AMI_ID"
echo ""
echo "  2. Deploy cluster:"
echo "     pcluster create-cluster --cluster-name hpc-optimization \\"
echo "       --cluster-configuration aws/cluster-config-with-ami.yaml"
echo ""
echo "  3. On first boot, run:"
echo "     /opt/hpc-optimization/bin/setup-shared.sh"
echo ""
echo "Estimated cost:"
echo "  Build time: ~20 minutes × \$0.34/hour = \$0.11"
echo "  AMI storage: ~10GB × \$0.05/GB-month = \$0.50/month"
echo ""
