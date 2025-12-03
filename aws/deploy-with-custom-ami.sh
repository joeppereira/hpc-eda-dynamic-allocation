#!/bin/bash
# Simple Deployment with Custom AMI
# Everything pre-installed, just deploy and go!

set -e

echo "=========================================="
echo "Deploy HPC Optimization Cluster"
echo "Using Custom AMI (Everything Pre-installed)"
echo "=========================================="
echo ""

# Check if custom AMI exists
if [ ! -f "aws/custom-ami-id.txt" ]; then
    echo "❌ Custom AMI not found!"
    echo ""
    echo "Please build custom AMI first:"
    echo "  ./aws/build-custom-ami.sh"
    echo ""
    exit 1
fi

# Load AMI ID
source aws/custom-ami-id.txt

echo "Configuration:"
echo "  Custom AMI: $AMI_ID"
echo "  Region: $REGION"
echo ""

# Configuration
CLUSTER_NAME="hpc-optimization"
KEY_NAME="eda-cluster-key"
SUBNET_ID="subnet-06b3a8f511e1f1213"

# Create cluster configuration with custom AMI
cat > aws/cluster-config-with-ami.yaml <<EOF
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
      Script: s3://hpc-optimization-$(aws sts get-caller-identity --query Account --output text)/scripts/setup-head-custom-ami.sh

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
          Script: s3://hpc-optimization-$(aws sts get-caller-identity --query Account --output text)/scripts/setup-compute-custom-ami.sh
  SlurmSettings:
    ScaledownIdletime: 5
    EnableMemoryBasedScheduling: true

slurm:
  ParallelClusterConfig:
    ComputeNodeAmi: $AMI_ID

SharedStorage:
  - MountDir: /shared
    Name: shared-efs
    StorageType: Efs
    EfsSettings:
      ThroughputMode: bursting
      PerformanceMode: generalPurpose
      Encrypted: true

Monitoring:
  DetailedMonitoring: false
  Logs:
    CloudWatch:
      Enabled: true
      RetentionInDays: 3

Tags:
  - Key: Project
    Value: HPC-Resource-Optimization
  - Key: Environment
    Value: Development
  - Key: CustomAMI
    Value: $AMI_ID
EOF

echo "✓ Cluster configuration created"
echo ""

# Create simple setup scripts (everything already installed in AMI)
BUCKET_NAME="hpc-optimization-$(aws sts get-caller-identity --query Account --output text)"

# Head node setup (minimal - just copy to shared)
cat > /tmp/setup-head-custom-ami.sh <<'HEADSCRIPT'
#!/bin/bash
set -e
echo "=== Head Node Setup (Custom AMI) ==="

# Everything already installed, just setup shared storage
/opt/hpc-optimization/bin/setup-shared.sh

# Configure SPANK plugin
echo "required /shared/spank/spank_monitor.so" | sudo tee /opt/slurm/etc/plugstack.conf

# Start prediction API
cat > /tmp/prediction-api.service <<EOF
[Unit]
Description=HPC Resource Prediction API
After=network.target

[Service]
Type=simple
User=ec2-user
WorkingDirectory=/shared/hpc-optimization
ExecStart=/usr/bin/singularity exec /shared/containers/openroad.sif python3 -m uvicorn prediction.api:app --host 0.0.0.0 --port 8000
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

sudo mv /tmp/prediction-api.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable prediction-api
sudo systemctl start prediction-api

echo "✓ Head node ready!"
HEADSCRIPT

# Compute node setup (minimal - just configure SPANK)
cat > /tmp/setup-compute-custom-ami.sh <<'COMPUTESCRIPT'
#!/bin/bash
set -e
echo "=== Compute Node Setup (Custom AMI) ==="

# Everything already installed, just configure SPANK
echo "required /shared/spank/spank_monitor.so" | sudo tee /opt/slurm/etc/plugstack.conf

# Restart slurmd to load SPANK plugin
sudo systemctl restart slurmd

echo "✓ Compute node ready!"
COMPUTESCRIPT

# Upload scripts
aws s3 cp /tmp/setup-head-custom-ami.sh "s3://$BUCKET_NAME/scripts/"
aws s3 cp /tmp/setup-compute-custom-ami.sh "s3://$BUCKET_NAME/scripts/"

echo "✓ Setup scripts uploaded"
echo ""

# Validate configuration
echo "Validating cluster configuration..."
pcluster create-cluster \
    --cluster-name $CLUSTER_NAME \
    --cluster-configuration aws/cluster-config-with-ami.yaml \
    --region $REGION \
    --dryrun true 2>&1 | grep -q "DryRun flag is set" && {
    echo "✓ Configuration validated"
} || {
    echo "❌ Configuration validation failed"
    exit 1
}
echo ""

# Deploy cluster
echo "Deploying cluster..."
echo "This will take 10-15 minutes (faster with custom AMI!)"
echo ""

read -p "Proceed with deployment? (yes/no): " CONFIRM
if [ "$CONFIRM" != "yes" ]; then
    echo "Deployment cancelled"
    exit 0
fi

pcluster create-cluster \
    --cluster-name $CLUSTER_NAME \
    --cluster-configuration aws/cluster-config-with-ami.yaml \
    --region $REGION

echo ""
echo "=========================================="
echo "Cluster Deployment Started!"
echo "=========================================="
echo ""
echo "Monitor progress:"
echo "  watch -n 10 'pcluster describe-cluster --cluster-name $CLUSTER_NAME --region $REGION | grep clusterStatus'"
echo ""
echo "SSH when ready:"
echo "  pcluster ssh --cluster-name $CLUSTER_NAME -i ~/.ssh/$KEY_NAME.pem --region $REGION"
echo ""
echo "Test OpenROAD:"
echo "  singularity exec /shared/containers/openroad.sif openroad -version"
echo ""
echo "Submit test job:"
echo "  sbatch --wrap='singularity exec /shared/containers/openroad.sif openroad -version'"
echo ""
echo "Check SPANK plugin:"
echo "  scontrol show config | grep -i spank"
echo "  ls /shared/metrics/"
echo ""
echo "Estimated time: 10-15 minutes"
echo "Estimated cost: ~\$0.20/hour (idle)"
echo ""
