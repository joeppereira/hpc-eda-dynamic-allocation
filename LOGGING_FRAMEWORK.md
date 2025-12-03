# Logging Framework - Complete Audit Trail

**Purpose**: Comprehensive logging of all operations for validation and reproducibility

---

## 📊 What Gets Logged

### 1. Infrastructure Logs (AWS)

**CloudFormation Events**:
```bash
aws cloudformation describe-stack-events \
    --stack-name hpc-optimization \
    --region us-east-1 \
    --output json \
    > logs/cloudformation-$(date +%Y%m%d-%H%M%S).json
```

**ParallelCluster Logs**:
```bash
aws logs tail /aws/parallelcluster/hpc-optimization-* \
    --since 24h \
    --format short \
    > logs/parallelcluster-$(date +%Y%m%d-%H%M%S).log
```

**EC2 Instance Logs**:
```bash
aws ec2 describe-instances \
    --filters "Name=tag:parallelcluster:cluster-name,Values=hpc-optimization" \
    --output json \
    > logs/ec2-instances-$(date +%Y%m%d-%H%M%S).json
```

### 2. SLURM Logs

**Job Accounting**:
```bash
# All jobs
sacct --format=ALL --starttime $(date -d '1 day ago' +%Y-%m-%d) \
    > logs/slurm-accounting-$(date +%Y%m%d).txt

# Detailed format
sacct -S today --format=JobID,JobName,User,Partition,State,AllocCPUS,ReqMem,MaxRSS,Elapsed,Start,End \
    > logs/slurm-jobs-$(date +%Y%m%d).txt
```

**Queue Status**:
```bash
sinfo > logs/slurm-partitions-$(date +%Y%m%d-%H%M%S).txt
squeue > logs/slurm-queue-$(date +%Y%m%d-%H%M%S).txt
```

**SLURM Configuration**:
```bash
scontrol show config > logs/slurm-config-$(date +%Y%m%d).txt
```

### 3. Job Logs

**Job Output Files**:
```bash
# Automatically saved by SLURM
#SBATCH --output=/shared/logs/job_%j.out
#SBATCH --error=/shared/logs/job_%j.err

# Location: /shared/logs/job_*.out
```

**Job Metadata**:
```bash
# For each job
scontrol show job <JOB_ID> > logs/job-<JOB_ID>-metadata.txt
```

### 4. SPANK Plugin Logs

**Metrics Files**:
```bash
# Exported by SPANK plugin
# Location: /shared/metrics/job_<JOB_ID>.json

# Example content:
{
  "job_id": "12345",
  "start_time": "2025-11-11T16:00:00Z",
  "end_time": "2025-11-11T16:30:00Z",
  "stages": [
    {
      "stage_name": "synthesis",
      "cpu_util_avg": 85.3,
      "memory_peak_gb": 12.5,
      "duration_sec": 600
    }
  ]
}
```

**SPANK Plugin Errors**:
```bash
# Check syslog for SPANK errors
sudo grep -i spank /var/log/messages > logs/spank-errors.log
```

### 5. ML Training Logs

**Training Output**:
```python
# In prediction/train_model.py
import logging

logging.basicConfig(
    filename='logs/ml-training.log',
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)

logger.info(f"Training started with {len(X_train)} samples")
logger.info(f"Model accuracy: {score}")
logger.info(f"Model saved to {model_path}")
```

**Model Metrics**:
```bash
# Save model evaluation
python3 scripts/evaluate_model.py > logs/model-evaluation-$(date +%Y%m%d).txt
```

### 6. API Logs

**FastAPI Access Logs**:
```python
# In prediction/api.py
import logging

logging.basicConfig(
    filename='logs/api-access.log',
    level=logging.INFO
)

@app.post("/predict")
async def predict(features: DesignFeatures):
    logger.info(f"Prediction request: {features}")
    result = model.predict(features)
    logger.info(f"Prediction result: {result}")
    return result
```

**API Health Checks**:
```bash
# Periodic health checks
curl http://localhost:8000/health >> logs/api-health-$(date +%Y%m%d).log
```

### 7. Resource Monitoring Logs

**System Metrics**:
```bash
# CPU, memory, disk usage
top -b -n 1 > logs/system-top-$(date +%Y%m%d-%H%M%S).txt
free -h > logs/system-memory-$(date +%Y%m%d-%H%M%S).txt
df -h > logs/system-disk-$(date +%Y%m%d-%H%M%S).txt
```

**CloudWatch Metrics**:
```bash
# EC2 metrics
aws cloudwatch get-metric-statistics \
    --namespace AWS/EC2 \
    --metric-name CPUUtilization \
    --dimensions Name=InstanceId,Value=i-xxxxx \
    --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
    --period 300 \
    --statistics Average \
    > logs/cloudwatch-cpu-$(date +%Y%m%d-%H%M%S).json
```

---

## 🔧 Automated Logging Scripts

### Master Logging Script

```bash
#!/bin/bash
# collect-all-logs.sh - Collect all system logs

set -e

TIMESTAMP=$(date +%Y%m%d-%H%M%S)
LOG_DIR="logs/collection-$TIMESTAMP"
mkdir -p $LOG_DIR/{aws,slurm,jobs,metrics,system,ml,api}

echo "Collecting logs to $LOG_DIR..."

# 1. AWS Infrastructure
echo "[1/8] AWS infrastructure logs..."
pcluster describe-cluster --cluster-name hpc-optimization --region us-east-1 \
    > $LOG_DIR/aws/cluster-info.json 2>&1 || echo "Failed"

aws cloudformation describe-stack-events --stack-name hpc-optimization \
    > $LOG_DIR/aws/cloudformation-events.json 2>&1 || echo "Failed"

aws s3 ls s3://hpc-optimization-857483395393/ --recursive \
    > $LOG_DIR/aws/s3-contents.txt 2>&1 || echo "Failed"

# 2. SLURM Status
echo "[2/8] SLURM logs..."
sinfo > $LOG_DIR/slurm/partitions.txt 2>&1 || echo "Not on cluster"
squeue > $LOG_DIR/slurm/queue.txt 2>&1 || echo "Not on cluster"
sacct -S today --format=ALL > $LOG_DIR/slurm/accounting.txt 2>&1 || echo "Not on cluster"
scontrol show config > $LOG_DIR/slurm/config.txt 2>&1 || echo "Not on cluster"

# 3. Job Logs
echo "[3/8] Job logs..."
if [ -d "/shared/logs" ]; then
    cp /shared/logs/*.out $LOG_DIR/jobs/ 2>/dev/null || echo "No job logs"
    cp /shared/logs/*.err $LOG_DIR/jobs/ 2>/dev/null || echo "No error logs"
fi

# 4. SPANK Metrics
echo "[4/8] SPANK metrics..."
if [ -d "/shared/metrics" ]; then
    cp /shared/metrics/*.json $LOG_DIR/metrics/ 2>/dev/null || echo "No metrics"
fi

# 5. System Status
echo "[5/8] System status..."
top -b -n 1 > $LOG_DIR/system/top.txt 2>&1 || echo "Failed"
free -h > $LOG_DIR/system/memory.txt 2>&1 || echo "Failed"
df -h > $LOG_DIR/system/disk.txt 2>&1 || echo "Failed"
uptime > $LOG_DIR/system/uptime.txt 2>&1 || echo "Failed"

# 6. ML Logs
echo "[6/8] ML logs..."
if [ -f "logs/ml-training.log" ]; then
    cp logs/ml-training.log $LOG_DIR/ml/
fi
if [ -f "prediction/trained_model.pkl" ]; then
    ls -lh prediction/trained_model.pkl > $LOG_DIR/ml/model-info.txt
fi

# 7. API Logs
echo "[7/8] API logs..."
if [ -f "logs/api-access.log" ]; then
    cp logs/api-access.log $LOG_DIR/api/
fi
curl -s http://localhost:8000/health > $LOG_DIR/api/health.json 2>&1 || echo "API not running"

# 8. Git Status
echo "[8/8] Git status..."
git log --oneline -10 > $LOG_DIR/git-log.txt 2>&1 || echo "Not a git repo"
git status > $LOG_DIR/git-status.txt 2>&1 || echo "Not a git repo"

# Create summary
cat > $LOG_DIR/SUMMARY.txt <<EOF
Log Collection Summary
======================
Timestamp: $TIMESTAMP
Collected by: $(whoami)
Host: $(hostname)

Contents:
- AWS infrastructure logs
- SLURM status and accounting
- Job output logs
- SPANK plugin metrics
- System resource usage
- ML training logs
- API access logs
- Git repository status

Total size: $(du -sh $LOG_DIR | cut -f1)
EOF

echo ""
echo "✓ Logs collected in $LOG_DIR"
echo "  Summary: $LOG_DIR/SUMMARY.txt"
echo "  Size: $(du -sh $LOG_DIR | cut -f1)"
```

### Continuous Monitoring Script

```bash
#!/bin/bash
# monitor-continuous.sh - Continuous monitoring with logging

LOG_FILE="logs/continuous-monitor-$(date +%Y%m%d).log"

while true; do
    TIMESTAMP=$(date +"%Y-%m-%d %H:%M:%S")
    
    # SLURM queue
    QUEUE_COUNT=$(squeue -h | wc -l)
    
    # Running jobs
    RUNNING=$(squeue -h -t RUNNING | wc -l)
    
    # Pending jobs
    PENDING=$(squeue -h -t PENDING | wc -l)
    
    # System load
    LOAD=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}')
    
    # Memory usage
    MEM=$(free | grep Mem | awk '{printf "%.1f", $3/$2 * 100}')
    
    # Log entry
    echo "$TIMESTAMP | Queue: $QUEUE_COUNT | Running: $RUNNING | Pending: $PENDING | Load: $LOAD | Mem: $MEM%" \
        >> $LOG_FILE
    
    sleep 60  # Every minute
done
```

---

## 📈 Log Analysis Scripts

### Job Efficiency Analysis

```python
#!/usr/bin/env python3
# analyze-job-efficiency.py

import subprocess
import json
from datetime import datetime

def analyze_jobs():
    """Analyze job efficiency from SLURM accounting"""
    
    # Get job data
    cmd = "sacct -S today --format=JobID,AllocCPUS,ReqMem,MaxRSS,CPUTimeRAW,ElapsedRaw --parsable2 --noheader"
    result = subprocess.run(cmd, shell=True, capture_output=True, text=True)
    
    jobs = []
    for line in result.stdout.strip().split('\n'):
        if not line:
            continue
        parts = line.split('|')
        if len(parts) < 6:
            continue
            
        job_id, cpus, req_mem, max_rss, cpu_time, elapsed = parts
        
        # Calculate efficiency
        try:
            cpus = int(cpus)
            cpu_time = int(cpu_time)
            elapsed = int(elapsed)
            
            cpu_efficiency = (cpu_time / (cpus * elapsed)) * 100 if elapsed > 0 else 0
            
            # Parse memory
            req_mem_gb = parse_memory(req_mem)
            max_rss_gb = parse_memory(max_rss)
            mem_efficiency = (max_rss_gb / req_mem_gb) * 100 if req_mem_gb > 0 else 0
            
            jobs.append({
                'job_id': job_id,
                'cpus': cpus,
                'req_mem_gb': req_mem_gb,
                'max_rss_gb': max_rss_gb,
                'cpu_efficiency': cpu_efficiency,
                'mem_efficiency': mem_efficiency,
                'elapsed': elapsed
            })
        except:
            continue
    
    # Save analysis
    with open(f'logs/job-efficiency-{datetime.now().strftime("%Y%m%d")}.json', 'w') as f:
        json.dump(jobs, f, indent=2)
    
    # Print summary
    if jobs:
        avg_cpu_eff = sum(j['cpu_efficiency'] for j in jobs) / len(jobs)
        avg_mem_eff = sum(j['mem_efficiency'] for j in jobs) / len(jobs)
        
        print(f"Analyzed {len(jobs)} jobs")
        print(f"Average CPU efficiency: {avg_cpu_eff:.1f}%")
        print(f"Average Memory efficiency: {avg_mem_eff:.1f}%")
    
    return jobs

def parse_memory(mem_str):
    """Parse memory string to GB"""
    if not mem_str or mem_str == '':
        return 0
    
    mem_str = mem_str.upper().replace('N', '')
    
    if 'G' in mem_str:
        return float(mem_str.replace('G', ''))
    elif 'M' in mem_str:
        return float(mem_str.replace('M', '')) / 1024
    elif 'K' in mem_str:
        return float(mem_str.replace('K', '')) / (1024 * 1024)
    else:
        return float(mem_str) / (1024 * 1024 * 1024)

if __name__ == '__main__':
    analyze_jobs()
```

---

## 🎯 Validation Logging

### Pre-Deployment Validation Log

```bash
#!/bin/bash
# validate-pre-deployment.sh

LOG_FILE="logs/validation-pre-deployment-$(date +%Y%m%d-%H%M%S).log"

{
    echo "=========================================="
    echo "Pre-Deployment Validation"
    echo "=========================================="
    echo "Timestamp: $(date)"
    echo ""
    
    echo "[1] AWS CLI"
    aws --version && echo "✓ PASS" || echo "✗ FAIL"
    echo ""
    
    echo "[2] AWS Credentials"
    aws sts get-caller-identity && echo "✓ PASS" || echo "✗ FAIL"
    echo ""
    
    echo "[3] ParallelCluster CLI"
    pcluster version && echo "✓ PASS" || echo "✗ FAIL"
    echo ""
    
    echo "[4] EC2 Key Pair"
    aws ec2 describe-key-pairs --key-names eda-cluster-key && echo "✓ PASS" || echo "✗ FAIL"
    echo ""
    
    echo "[5] VPC and Subnets"
    aws ec2 describe-vpcs --vpc-ids vpc-0b30951358f00a943 && echo "✓ PASS" || echo "✗ FAIL"
    echo ""
    
    echo "[6] Project Files"
    ls -la spank/spank_monitor.c && echo "✓ PASS" || echo "✗ FAIL"
    ls -la prediction/model.py && echo "✓ PASS" || echo "✗ FAIL"
    ls -la database/schema.py && echo "✓ PASS" || echo "✗ FAIL"
    echo ""
    
    echo "=========================================="
    echo "Validation Complete"
    echo "=========================================="
} | tee $LOG_FILE

echo "Log saved to: $LOG_FILE"
```

### Post-Deployment Validation Log

```bash
#!/bin/bash
# validate-post-deployment.sh

LOG_FILE="logs/validation-post-deployment-$(date +%Y%m%d-%H%M%S).log"

{
    echo "=========================================="
    echo "Post-Deployment Validation"
    echo "=========================================="
    echo "Timestamp: $(date)"
    echo ""
    
    echo "[1] Cluster Status"
    pcluster describe-cluster --cluster-name hpc-optimization --region us-east-1 \
        | grep clusterStatus && echo "✓ PASS" || echo "✗ FAIL"
    echo ""
    
    echo "[2] Head Node Accessible"
    pcluster ssh --cluster-name hpc-optimization -i ~/.ssh/eda-cluster-key.pem --region us-east-1 \
        --command "echo 'SSH works'" && echo "✓ PASS" || echo "✗ FAIL"
    echo ""
    
    echo "[3] SLURM Running"
    pcluster ssh --cluster-name hpc-optimization -i ~/.ssh/eda-cluster-key.pem --region us-east-1 \
        --command "sinfo" && echo "✓ PASS" || echo "✗ FAIL"
    echo ""
    
    echo "[4] Shared Storage"
    pcluster ssh --cluster-name hpc-optimization -i ~/.ssh/eda-cluster-key.pem --region us-east-1 \
        --command "ls /shared" && echo "✓ PASS" || echo "✗ FAIL"
    echo ""
    
    echo "=========================================="
    echo "Validation Complete"
    echo "=========================================="
} | tee $LOG_FILE

echo "Log saved to: $LOG_FILE"
```

---

## 📦 Log Archival

### Archive Logs for History

```bash
#!/bin/bash
# archive-logs.sh - Archive all logs for historical record

ARCHIVE_NAME="hpc-optimization-logs-$(date +%Y%m%d-%H%M%S).tar.gz"

echo "Creating archive: $ARCHIVE_NAME"

tar -czf $ARCHIVE_NAME \
    logs/ \
    EXECUTION_LOG.md \
    VALIDATION_STATUS.md \
    LOGGING_FRAMEWORK.md \
    DEPLOYMENT_IN_PROGRESS.md \
    FINAL_SUMMARY.md \
    --exclude='*.tar.gz'

echo "✓ Archive created: $ARCHIVE_NAME"
echo "  Size: $(du -sh $ARCHIVE_NAME | cut -f1)"

# Upload to S3 for permanent storage
aws s3 cp $ARCHIVE_NAME s3://hpc-optimization-857483395393/archives/

echo "✓ Uploaded to S3"
```

---

## Summary

### What Gets Logged
1. ✅ AWS infrastructure (CloudFormation, EC2, S3)
2. ✅ SLURM (accounting, queue, config)
3. ✅ Job outputs (stdout, stderr)
4. ✅ SPANK metrics (JSON files)
5. ✅ ML training (logs, metrics)
6. ✅ API access (requests, responses)
7. ✅ System resources (CPU, memory, disk)
8. ✅ Validation results (pre/post deployment)

### Log Locations
- `logs/` - All log files
- `/shared/logs/` - Job output files (on cluster)
- `/shared/metrics/` - SPANK metrics (on cluster)
- CloudWatch Logs - AWS infrastructure
- SLURM accounting database - Job history

### Validation
- Pre-deployment validation logged
- Post-deployment validation logged
- Continuous monitoring logged
- Job efficiency analyzed and logged
- All logs archived for history

**Everything is logged and can be validated!**
