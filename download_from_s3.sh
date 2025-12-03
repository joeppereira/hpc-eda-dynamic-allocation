#!/bin/bash
# Download HPC Learning Results from S3 to your laptop

S3_BUCKET="s3://parallelcluster-e140fb2097b14600-v1-do-not-delete/hpc-learning-results"
DOWNLOAD_DIR="$HOME/Downloads/hpc-learning-results-$(date +%Y%m%d_%H%M%S)"

echo "════════════════════════════════════════════════════════════"
echo "  Download HPC Learning Results from S3"
echo "════════════════════════════════════════════════════════════"
echo ""

# Check AWS CLI
if ! command -v aws &> /dev/null; then
    echo "✗ AWS CLI not found"
    echo ""
    echo "Install with: brew install awscli"
    echo "Then run: aws configure"
    exit 1
fi

# Check AWS credentials
if ! aws sts get-caller-identity &> /dev/null; then
    echo "✗ AWS credentials not configured"
    echo ""
    echo "Run: aws configure"
    echo "Enter your AWS Access Key ID and Secret Access Key"
    exit 1
fi

echo "✓ AWS CLI configured"
echo ""

# Check bucket
echo "Checking S3 bucket..."
CONTENTS=$(aws s3 ls $S3_BUCKET/ 2>&1)

if [ $? -ne 0 ]; then
    echo "✗ Cannot access bucket:"
    echo "$CONTENTS"
    echo ""
    echo "Make sure you have permissions to access this bucket"
    exit 1
fi

if [ -z "$CONTENTS" ]; then
    echo "⚠ Bucket is empty"
    echo ""
    echo "The deployment script may not have finished yet."
    echo "Check job status on the cluster with: squeue"
    exit 0
fi

echo "✓ Bucket has data"
echo ""

# Show contents
echo "Bucket contents:"
echo "$CONTENTS"
echo ""

# Count files
FILE_COUNT=$(aws s3 ls $S3_BUCKET/ --recursive | wc -l)
TOTAL_SIZE=$(aws s3 ls $S3_BUCKET/ --recursive --summarize | grep "Total Size" | awk '{print $3}')
echo "Files: $FILE_COUNT"
echo "Total size: $TOTAL_SIZE bytes"
echo ""

# Download
echo "Downloading to: $DOWNLOAD_DIR"
mkdir -p "$DOWNLOAD_DIR"

aws s3 sync $S3_BUCKET/ "$DOWNLOAD_DIR/" --progress

if [ $? -eq 0 ]; then
    echo ""
    echo "✓ Download complete"
    echo ""
    
    # Extract archives
    cd "$DOWNLOAD_DIR"
    if ls *.tar.gz >/dev/null 2>&1; then
        echo "Extracting archives..."
        for archive in *.tar.gz; do
            echo "  Extracting: $archive"
            tar -xzf "$archive"
        done
        echo "✓ Extracted"
        echo ""
    fi
    
    # Show structure
    echo "Downloaded structure:"
    tree -L 2 "$DOWNLOAD_DIR" 2>/dev/null || find "$DOWNLOAD_DIR" -maxdepth 2 -type d
    echo ""
    
    # Verify key files
    echo "Verifying contents..."
    
    if find "$DOWNLOAD_DIR" -name "job_submit_learning.lua" | grep -q .; then
        echo "✓ Found: job_submit_learning.lua"
    fi
    
    if find "$DOWNLOAD_DIR" -name "learning_api.py" | grep -q .; then
        echo "✓ Found: learning_api.py"
    fi
    
    if find "$DOWNLOAD_DIR" -name "*.db" | grep -q .; then
        echo "✓ Found: database file"
    fi
    
    if find "$DOWNLOAD_DIR" -name "slurmctld.log" | grep -q .; then
        echo "✓ Found: SLURM logs"
    fi
    
    echo ""
    echo "════════════════════════════════════════════════════════════"
    echo "  Download Complete!"
    echo "════════════════════════════════════════════════════════════"
    echo ""
    echo "Location: $DOWNLOAD_DIR"
    echo ""
    echo "Open in Finder:"
    echo "  open \"$DOWNLOAD_DIR\""
    echo ""
    echo "View source code:"
    echo "  cd \"$DOWNLOAD_DIR\"/learning-results-*/source_code"
    echo ""
    
    # Open in Finder automatically
    open "$DOWNLOAD_DIR"
    
else
    echo ""
    echo "✗ Download failed"
    exit 1
fi
