#!/bin/bash
# Build Singularity container on AWS EC2 instance

set -e

echo "=========================================="
echo "Build Singularity Container on AWS"
echo "=========================================="
echo ""

# Configuration
REGION="us-east-1"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
BUCKET_NAME="hpc-optimization-${ACCOUNT_ID}"
KEY_NAME="eda-cluster-key"
SUBNET_ID="subnet-06b3a8f511e1f1213"
INSTANCE_TYPE="t3.large"  # 2 vCPU, 8GB RAM - enough for building

echo "Configuration:"
echo "  Region: $REGION"
echo "  S3 Bucket: $BUCKET_NAME"
echo "  Instance Type: $INSTANCE_TYPE"
echo ""

# Step 1: Launch build instance
echo "Step 1: Launching build instance..."

# Get latest Amazon Linux 2 AMI
AMI_ID=$(aws ec2 describe-images \
    --owners amazon \
    --filters "Name=name,Values=amzn2-ami-hvm-*-x86_64-gp2" \
    --query 'Images | sort_by(@, &CreationDate) | [-1].ImageId' \
    --output text \
    --region $REGION)

echo "Using AMI: $AMI_ID"

# Create security group for build instance
SG_ID=$(aws ec2 create-security-group \
    --group-name singularity-build-sg \
    --description "Security group for Singularity container build" \
    --region $REGION \
    --output text 2>/dev/null || \
    aws ec2 describe-security-groups \
        --filters "Name=group-name,Values=singularity-build-sg" \
        --query 'SecurityGroups[0].GroupId' \
        --output text \
        --region $REGION)

echo "Security Group: $SG_ID"

# Allow SSH from anywhere (temporary)
aws ec2 authorize-security-group-ingress \
    --group-id $SG_ID \
    --protocol tcp \
    --port 22 \
    --cidr 0.0.0.0/0 \
    --region $REGION 2>/dev/null || echo "SSH rule already exists"

# Launch instance
INSTANCE_ID=$(aws ec2 run-instances \
    --image-id $AMI_ID \
    --instance-type $INSTANCE_TYPE \
    --key-name $KEY_NAME \
    --subnet-id $SUBNET_ID \
    --security-group-ids $SG_ID \
    --iam-instance-profile Name=ecsInstanceRole \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=singularity-builder},{Key=Project,Value=HPC-Optimization}]" \
    --user-data file:///dev/stdin \
    --region $REGION \
    --query 'Instances[0].InstanceId' \
    --output text <<'USERDATA'
#!/bin/bash
# Install Singularity and build tools
yum update -y
yum install -y epel-release
yum install -y singularity-ce git
USERDATA
)

echo "✓ Launched instance: $INSTANCE_ID"
echo ""

# Step 2: Wait for instance to be running
echo "Step 2: Waiting for instance to be running..."
aws ec2 wait instance-running \
    --instance-ids $INSTANCE_ID \
    --region $REGION

# Get public IP
PUBLIC_IP=$(aws ec2 describe-instances \
    --instance-ids $INSTANCE_ID \
    --query 'Reservations[0].Instances[0].PublicIpAddress' \
    --output text \
    --region $REGION)

echo "✓ Instance running at: $PUBLIC_IP"
echo "  Waiting 60 seconds for user-data script to complete..."
sleep 60
echo ""

# Step 3: Build Singularity container
echo "Step 3: Building Singularity container on instance..."

# Create build script
cat > /tmp/build-singularity.sh <<'BUILDSCRIPT'
#!/bin/bash
set -e

echo "=== Building Singularity Container ==="

# Wait for Singularity to be installed
while ! command -v singularity &> /dev/null; do
    echo "Waiting for Singularity installation..."
    sleep 5
done

singularity --version

# Convert Docker image to Singularity
echo "Converting OpenROAD Docker image to Singularity..."
cd /tmp
singularity pull openroad.sif docker://openroad/flow-ubuntu:latest

echo "✓ Container built successfully"
ls -lh openroad.sif

# Upload to S3
echo "Uploading to S3..."
aws s3 cp openroad.sif s3://BUCKET_NAME/containers/openroad.sif

echo "✓ Upload complete"
BUILDSCRIPT

# Replace bucket name
sed "s|BUCKET_NAME|$BUCKET_NAME|g" /tmp/build-singularity.sh > /tmp/build-singularity-final.sh

# Copy script to instance and execute
echo "Copying build script to instance..."
scp -i ~/.ssh/$KEY_NAME.pem \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    /tmp/build-singularity-final.sh \
    ec2-user@$PUBLIC_IP:/tmp/build.sh

echo "Executing build script..."
ssh -i ~/.ssh/$KEY_NAME.pem \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    ec2-user@$PUBLIC_IP \
    "chmod +x /tmp/build.sh && /tmp/build.sh"

echo ""
echo "✓ Container built and uploaded to S3!"
echo ""

# Step 4: Cleanup
echo "Step 4: Cleaning up..."
read -p "Terminate build instance? (yes/no): " TERMINATE

if [ "$TERMINATE" = "yes" ]; then
    aws ec2 terminate-instances \
        --instance-ids $INSTANCE_ID \
        --region $REGION
    echo "✓ Instance terminating: $INSTANCE_ID"
else
    echo "⚠ Instance still running: $INSTANCE_ID"
    echo "  Terminate manually: aws ec2 terminate-instances --instance-ids $INSTANCE_ID --region $REGION"
fi

echo ""
echo "=========================================="
echo "Container Build Complete!"
echo "=========================================="
echo ""
echo "Container location:"
echo "  s3://$BUCKET_NAME/containers/openroad.sif"
echo ""
echo "Download locally:"
echo "  aws s3 cp s3://$BUCKET_NAME/containers/openroad.sif ."
echo ""
echo "Use in cluster:"
echo "  singularity exec /shared/containers/openroad.sif openroad -version"
echo ""
