#!/bin/bash
# Pre-deployment verification script
# Run this before deploying to AWS to check prerequisites

set -e

echo "=========================================="
echo "AWS Parallel Cluster Pre-Deployment Check"
echo "=========================================="
echo ""

ERRORS=0
WARNINGS=0

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

check_pass() {
    echo -e "${GREEN}✓${NC} $1"
}

check_fail() {
    echo -e "${RED}✗${NC} $1"
    ((ERRORS++))
}

check_warn() {
    echo -e "${YELLOW}⚠${NC} $1"
    ((WARNINGS++))
}

# Check 1: AWS CLI installed
echo "Checking AWS CLI..."
if command -v aws &> /dev/null; then
    AWS_VERSION=$(aws --version 2>&1 | cut -d' ' -f1)
    check_pass "AWS CLI installed: $AWS_VERSION"
else
    check_fail "AWS CLI not installed. Install: pip3 install awscli"
fi

# Check 2: AWS credentials configured
echo ""
echo "Checking AWS credentials..."
if aws sts get-caller-identity &> /dev/null; then
    ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    REGION=$(aws configure get region)
    check_pass "AWS credentials configured"
    echo "  Account ID: $ACCOUNT_ID"
    echo "  Region: $REGION"
else
    check_fail "AWS credentials not configured. Run: aws configure"
fi

# Check 3: ParallelCluster CLI installed
echo ""
echo "Checking ParallelCluster CLI..."
if command -v pcluster &> /dev/null; then
    PCLUSTER_VERSION=$(pcluster version 2>&1)
    check_pass "ParallelCluster CLI installed: $PCLUSTER_VERSION"
else
    check_fail "ParallelCluster CLI not installed. Install: pip3 install aws-parallelcluster"
fi

# Check 4: Check for EC2 key pairs
echo ""
echo "Checking EC2 key pairs..."
KEY_PAIRS=$(aws ec2 describe-key-pairs --query 'KeyPairs[*].KeyName' --output text 2>/dev/null || echo "")
if [ -n "$KEY_PAIRS" ]; then
    check_pass "EC2 key pairs found:"
    for key in $KEY_PAIRS; do
        echo "  - $key"
    done
else
    check_warn "No EC2 key pairs found. Create one in AWS Console or with: aws ec2 create-key-pair"
fi

# Check 5: Check for VPCs and subnets
echo ""
echo "Checking VPC and subnets..."
VPCS=$(aws ec2 describe-vpcs --query 'Vpcs[*].VpcId' --output text 2>/dev/null || echo "")
if [ -n "$VPCS" ]; then
    check_pass "VPCs found:"
    for vpc in $VPCS; do
        echo "  - $vpc"
        # Get subnets for this VPC
        SUBNETS=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$vpc" --query 'Subnets[*].[SubnetId,AvailabilityZone,CidrBlock]' --output text 2>/dev/null || echo "")
        if [ -n "$SUBNETS" ]; then
            echo "$SUBNETS" | while read subnet az cidr; do
                echo "    Subnet: $subnet ($az) - $cidr"
            done
        fi
    done
else
    check_fail "No VPCs found. Create a VPC in AWS Console"
fi

# Check 6: Check cluster configuration file
echo ""
echo "Checking cluster configuration..."
if [ -f "aws/cluster-config.yaml" ]; then
    check_pass "Cluster configuration file exists"
    
    # Check for placeholder values
    if grep -q "subnet-XXXXXXXX" aws/cluster-config.yaml; then
        check_warn "Cluster config contains placeholder subnet IDs - needs updating"
    fi
    
    if grep -q "your-key-pair" aws/cluster-config.yaml; then
        check_warn "Cluster config contains placeholder key pair name - needs updating"
    fi
    
    if grep -q "your-bucket" aws/cluster-config.yaml; then
        check_warn "Cluster config contains placeholder S3 bucket - needs updating"
    fi
else
    check_fail "Cluster configuration file not found: aws/cluster-config.yaml"
fi

# Check 7: Check EC2 instance limits
echo ""
echo "Checking EC2 instance limits..."
# This requires Service Quotas API
LIMIT_CHECK=$(aws service-quotas get-service-quota \
    --service-code ec2 \
    --quota-code L-1216C47A \
    --query 'Quota.Value' \
    --output text 2>/dev/null || echo "unknown")

if [ "$LIMIT_CHECK" != "unknown" ]; then
    if [ $(echo "$LIMIT_CHECK >= 10" | bc) -eq 1 ]; then
        check_pass "EC2 vCPU limit sufficient: $LIMIT_CHECK vCPUs"
    else
        check_warn "EC2 vCPU limit may be low: $LIMIT_CHECK vCPUs (need ~160 for 10 c5.4xlarge nodes)"
    fi
else
    check_warn "Could not check EC2 limits. Verify in AWS Console: Service Quotas > EC2"
fi

# Check 8: Python packages
echo ""
echo "Checking Python packages..."
REQUIRED_PACKAGES=("numpy" "pandas" "scikit-learn" "psutil" "sqlalchemy" "fastapi")
for pkg in "${REQUIRED_PACKAGES[@]}"; do
    if python3 -c "import $pkg" 2>/dev/null; then
        check_pass "Python package installed: $pkg"
    else
        check_warn "Python package missing: $pkg (install: pip3 install $pkg)"
    fi
done

# Check 9: Project files
echo ""
echo "Checking project files..."
REQUIRED_FILES=(
    "database/schema.py"
    "monitoring/resource_monitor.py"
    "prediction/model.py"
    "prediction/train_model.py"
)

for file in "${REQUIRED_FILES[@]}"; do
    if [ -f "$file" ]; then
        check_pass "Project file exists: $file"
    else
        check_fail "Project file missing: $file"
    fi
done

# Summary
echo ""
echo "=========================================="
echo "Pre-Deployment Check Summary"
echo "=========================================="
echo ""

if [ $ERRORS -eq 0 ] && [ $WARNINGS -eq 0 ]; then
    echo -e "${GREEN}✓ All checks passed! Ready to deploy.${NC}"
    echo ""
    echo "Next steps:"
    echo "1. Update aws/cluster-config.yaml with your AWS IDs"
    echo "2. Create S3 bucket: aws s3 mb s3://hpc-optimization-scripts-YOUR-ACCOUNT-ID"
    echo "3. Upload scripts: aws s3 cp aws/scripts/ s3://your-bucket/scripts/ --recursive"
    echo "4. Follow aws/DEPLOYMENT_GUIDE.md"
    exit 0
elif [ $ERRORS -eq 0 ]; then
    echo -e "${YELLOW}⚠ $WARNINGS warning(s) found. Review and fix before deploying.${NC}"
    exit 0
else
    echo -e "${RED}✗ $ERRORS error(s) and $WARNINGS warning(s) found. Fix errors before deploying.${NC}"
    exit 1
fi
