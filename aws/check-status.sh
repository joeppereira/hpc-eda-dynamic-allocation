#!/bin/bash
# Check cluster status

CLUSTER_NAME="hpc-optimization"
REGION="us-east-1"

echo "=========================================="
echo "Cluster Status Check"
echo "=========================================="
echo ""

pcluster describe-cluster \
    --cluster-name $CLUSTER_NAME \
    --region $REGION \
    --query 'clusterStatus' \
    --output text

echo ""
echo "Full status:"
pcluster describe-cluster \
    --cluster-name $CLUSTER_NAME \
    --region $REGION
