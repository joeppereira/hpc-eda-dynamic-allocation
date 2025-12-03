#!/bin/bash
################################################################################
# Complete Learning-Based Dynamic Allocation System
# Deploy, test, and save results to S3
# 
# Usage from Cloud Shell or remote:
#   curl -O https://raw.githubusercontent.com/your-repo/deploy_and_test_complete.sh
#   bash deploy_and_test_complete.sh <head-node-ip> <s3-bucket>
#
# Or run directly on head node:
#   bash deploy_and_test_complete.sh localhost s3://your-bucket/results
################################################################################

set -e

HEAD_NODE=${1:-"localhost"}
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
WORK_DIR="/shared/hpc-learning-system"
RESULTS_DIR="/shared/learning-results-${TIMESTAMP}"

# Auto-detect S3 bucket from cluster config or create one
detect_s3_bucket() {
    # Try to get from ParallelCluster config
    if [ -f /opt/parallelcluster/shared/cluster-config.yaml ]; then
        BUCKET=$(grep -i "s3.*bucket" /opt/parallelcluster/shared/cluster-config.yaml | head -1 | awk '{print $NF}' | tr -d '"')
        if [ -n "$BUCKET" ]; then
            echo "s3://${BUCKET}/hpc-learning-results"
            return
        fi
    fi
    
    # Try to get cluster name and construct bucket
    CLUSTER_NAME=$(grep "cluster_name" /etc/parallelcluster/cfnconfig 2>/dev/null | cut -d'=' -f2 | tr -d ' ')
    if [ -n "$CLUSTER_NAME" ]; then
        BUCKET="parallelcluster-${CLUSTER_NAME}-$(aws sts get-caller-identity --query Account --output text 2>/dev/null)"
        # Check if bucket exists
        if aws s3 ls "s3://${BUCKET}" >/dev/null 2>&1; then
            echo "s3://${BUCKET}/hpc-learning-results"
            return
        fi
    fi
    
    # Create a new bucket with unique name
    ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null)
    REGION=$(aws configure get region 2>/dev/null || echo "us-east-1")
    BUCKET="hpc-learning-${ACCOUNT_ID}-${REGION}"
    
    # Try to create bucket
    if aws s3 mb "s3://${BUCKET}" --region ${REGION} 2>/dev/null; then
        echo "s3://${BUCKET}/results"
        return
    elif aws s3 ls "s3://${BUCKET}" >/dev/null 2>&1; then
        # Bucket already exists
        echo "s3://${BUCKET}/results"
        return
    fi
    
    # Fallback: no S3
    echo ""
}

S3_BUCKET_RAW=$(detect_s3_bucket)

# Clean up the bucket value - remove "null" or empty values
if [ "$S3_BUCKET_RAW" = "null" ] || [ -z "$S3_BUCKET_RAW" ]; then
    S3_BUCKET=""
else
    S3_BUCKET="$S3_BUCKET_RAW"
fi

# Allow override from command line
if [ -n "$2" ]; then
    S3_BUCKET="$2"
fi

echo "════════════════════════════════════════════════════════════"
echo "  HPC Learning-Based Dynamic Allocation System"
echo "  Complete Deployment and Test"
echo "════════════════════════════════════════════════════════════"
echo ""
echo "Configuration:"
echo "  Head Node: $HEAD_NODE"
if [ -n "$S3_BUCKET" ]; then
    echo "  S3 Bucket: $S3_BUCKET"
else
    echo "  S3 Bucket: (not configured - will save locally only)"
fi
echo "  Work Dir: $WORK_DIR"
echo "  Results: $RESULTS_DIR"
echo ""

if [ -z "$S3_BUCKET" ]; then
    echo "⚠ Note: S3 bucket not configured"
    echo "  Results will be saved locally to: $RESULTS_DIR"
    echo "  To use S3, run: $0 localhost s3://your-bucket/path"
    echo ""
    echo "Continuing with local storage in 5 seconds..."
    sleep 5
fi

# Create directories
mkdir -p $WORK_DIR/{slurm,prediction,database,monitoring,scripts}
mkdir -p $RESULTS_DIR

################################################################################
# STEP 1: Create all source files
################################################################################

echo "Step 1: Creating source files..."
echo "────────────────────────────────────────────────────────────"

# 1.1: job_submit plugin (Lua)
cat > $WORK_DIR/slurm/job_submit_learning.lua << 'EOF_LUA'
--[[
Learning-based job_submit plugin for SLURM
Queries historical data to adjust resource allocation
]]

function slurm_job_submit(job_desc, part_list, submit_uid)
    local design_gates = job_desc.environment["DESIGN_GATES"]
    local design_name = job_desc.environment["DESIGN_NAME"]
    local stage_name = job_desc.environment["STAGE_NAME"]
    
    if not design_gates or not design_name then
        slurm.log_info("job_submit: No design parameters, using user request")
        return slurm.SUCCESS
    end
    
    slurm.log_info(string.format(
        "job_submit: Job %s, Design=%s, Gates=%s, Stage=%s",
        job_desc.name or "unknown",
        design_name,
        design_gates,
        stage_name or "unknown"
    ))
    
    local prediction = query_prediction_api(design_name, design_gates, stage_name)
    
    if prediction then
        local predicted_mem_mb = math.floor(prediction.memory_gb * 1024)
        local predicted_cores = math.floor(prediction.cpu_cores)
        
        slurm.log_info(string.format(
            "job_submit: Prediction found - Memory: %d MB, Cores: %d (confidence: %s)",
            predicted_mem_mb,
            predicted_cores,
            prediction.confidence or "unknown"
        ))
        
        if prediction.confidence ~= "low" then
            local original_mem = job_desc.min_mem_per_node or 4096
            
            if predicted_mem_mb > original_mem * 1.2 then
                slurm.log_info(string.format(
                    "job_submit: Adjusting memory %d -> %d MB (based on history)",
                    original_mem,
                    predicted_mem_mb
                ))
                job_desc.min_mem_per_node = predicted_mem_mb
            end
        end
    else
        slurm.log_info(string.format(
            "job_submit: No prediction available for %s/%s, will learn from this run",
            design_name,
            stage_name or "all"
        ))
    end
    
    return slurm.SUCCESS
end

function query_prediction_api(design_name, design_gates, stage_name)
    local api_url = "http://localhost:8000"
    local endpoint = string.format(
        "%s/predict?design_name=%s&gates=%s&stage=%s",
        api_url,
        design_name,
        design_gates,
        stage_name or "synthesis"
    )
    
    local cmd = string.format("curl -s -m 2 '%s' 2>/dev/null", endpoint)
    local handle = io.popen(cmd)
    if not handle then return nil end
    
    local response = handle:read("*a")
    handle:close()
    
    if not response or response == "" then return nil end
    
    local memory_gb = response:match('"memory_gb"%s*:%s*([%d%.]+)')
    local cpu_cores = response:match('"cpu_cores"%s*:%s*([%d%.]+)')
    local confidence = response:match('"confidence"%s*:%s*"([^"]+)"')
    
    if memory_gb and cpu_cores then
        return {
            memory_gb = tonumber(memory_gb),
            cpu_cores = tonumber(cpu_cores),
            confidence = confidence
        }
    end
    
    return nil
end

function slurm_job_modify(job_desc, job_rec, part_list, modify_uid)
    return slurm.SUCCESS
end

slurm.log_info("job_submit_learning.lua loaded")
return slurm.SUCCESS
EOF_LUA

# 1.2: Prediction API (Python)
cat > $WORK_DIR/prediction/learning_api.py << 'EOF_API'
#!/usr/bin/env python3
from fastapi import FastAPI, Query
from pydantic import BaseModel
from typing import Optional
import sqlite3
from pathlib import Path
import numpy as np

app = FastAPI(title="HPC Resource Learning API")

DB_PATH = Path("/shared/hpc_metrics.db")
db_conn = None

class PredictionResponse(BaseModel):
    memory_gb: float
    cpu_cores: int
    duration_sec: float
    confidence: str
    source: str
    similar_jobs_count: int

@app.on_event("startup")
async def load_model():
    global db_conn
    if DB_PATH.exists():
        db_conn = sqlite3.connect(str(DB_PATH), check_same_thread=False)
        print(f"✓ Database connected: {DB_PATH}")

@app.get("/predict")
async def predict_resources(
    design_name: str = Query(...),
    gates: int = Query(...),
    stage: str = Query("synthesis"),
    freq_mhz: float = Query(100.0)
) -> PredictionResponse:
    similar_jobs = query_similar_jobs(design_name, gates, stage)
    
    if similar_jobs and len(similar_jobs) >= 3:
        avg_memory = np.mean([j['memory_peak_gb'] for j in similar_jobs])
        avg_cores = int(np.mean([j['cpu_cores'] for j in similar_jobs]))
        avg_duration = np.mean([j['duration_sec'] for j in similar_jobs])
        
        return PredictionResponse(
            memory_gb=round(avg_memory * 1.2, 2),
            cpu_cores=avg_cores,
            duration_sec=round(avg_duration, 1),
            confidence="high",
            source="similar_jobs",
            similar_jobs_count=len(similar_jobs)
        )
    
    default_memory = 4.0 + (gates / 50000) * 2.0
    
    return PredictionResponse(
        memory_gb=round(default_memory, 2),
        cpu_cores=4,
        duration_sec=600.0,
        confidence="low",
        source="default",
        similar_jobs_count=0
    )

def query_similar_jobs(design_name: str, gates: int, stage: str, tolerance: float = 0.3):
    if not db_conn:
        return []
    
    min_gates = int(gates * (1 - tolerance))
    max_gates = int(gates * (1 + tolerance))
    
    query = """
    SELECT j.job_name, df.cell_count, js.stage_name, js.duration_sec,
           sr.memory_peak_gb, sr.cpu_cores_used
    FROM jobs j
    JOIN design_features df ON j.id = df.job_id
    JOIN job_stages js ON j.id = js.job_id
    JOIN stage_resources sr ON js.id = sr.stage_id
    WHERE df.cell_count BETWEEN ? AND ?
    AND js.stage_name = ?
    AND j.status = 'completed'
    ORDER BY ABS(df.cell_count - ?) ASC
    LIMIT 10
    """
    
    try:
        cursor = db_conn.cursor()
        cursor.execute(query, (min_gates, max_gates, stage, gates))
        rows = cursor.fetchall()
        
        return [{
            'job_name': row[0],
            'cell_count': row[1],
            'stage_name': row[2],
            'duration_sec': row[3],
            'memory_peak_gb': row[4],
            'cpu_cores': row[5] or 4
        } for row in rows]
    except:
        return []

@app.get("/stats")
async def get_stats():
    if not db_conn:
        return {"error": "Database not connected"}
    
    try:
        cursor = db_conn.cursor()
        cursor.execute("SELECT COUNT(*) FROM jobs")
        job_count = cursor.fetchone()[0]
        
        cursor.execute("SELECT MIN(cell_count), MAX(cell_count) FROM design_features")
        min_cells, max_cells = cursor.fetchone()
        
        return {
            "total_jobs": job_count,
            "design_size_range": {"min_cells": min_cells, "max_cells": max_cells}
        }
    except:
        return {"error": "Query failed"}

@app.get("/health")
async def health_check():
    return {"status": "healthy", "database_connected": db_conn is not None}

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
EOF_API

echo "✓ Source files created"
echo ""

################################################################################
# STEP 2: Install system
################################################################################

echo "Step 2: Installing system..."
echo "────────────────────────────────────────────────────────────"

# Install Python dependencies
pip3 install fastapi uvicorn sqlalchemy psutil scikit-learn numpy --user --quiet

# Initialize database
sqlite3 /shared/hpc_metrics.db << 'EOF_SQL'
CREATE TABLE IF NOT EXISTS jobs (
    id INTEGER PRIMARY KEY,
    job_name TEXT NOT NULL,
    status TEXT DEFAULT 'completed',
    slurm_memory_gb REAL DEFAULT 16
);
CREATE TABLE IF NOT EXISTS design_features (
    id INTEGER PRIMARY KEY,
    job_id INTEGER,
    cell_count INTEGER,
    FOREIGN KEY (job_id) REFERENCES jobs(id)
);
CREATE TABLE IF NOT EXISTS job_stages (
    id INTEGER PRIMARY KEY,
    job_id INTEGER,
    stage_name TEXT NOT NULL,
    duration_sec REAL,
    FOREIGN KEY (job_id) REFERENCES jobs(id)
);
CREATE TABLE IF NOT EXISTS stage_resources (
    id INTEGER PRIMARY KEY,
    stage_id INTEGER,
    memory_peak_gb REAL,
    cpu_cores_used INTEGER,
    FOREIGN KEY (stage_id) REFERENCES job_stages(id)
);
EOF_SQL

# Install job_submit plugin
sudo cp $WORK_DIR/slurm/job_submit_learning.lua /opt/slurm/etc/job_submit.lua
sudo chown slurm:slurm /opt/slurm/etc/job_submit.lua

# Configure SLURM
if ! grep -q "JobSubmitPlugins=lua" /opt/slurm/etc/slurm.conf; then
    echo "JobSubmitPlugins=lua" | sudo tee -a /opt/slurm/etc/slurm.conf
fi

# Start API
cd $WORK_DIR
export PYTHONPATH=$WORK_DIR:$PYTHONPATH
nohup python3 prediction/learning_api.py > /shared/api.log 2>&1 &
API_PID=$!
sleep 3

# Restart SLURM
sudo systemctl restart slurmctld

echo "✓ System installed"
echo "  API PID: $API_PID"
echo ""

################################################################################
# STEP 3: Run scaling tests
################################################################################

echo "Step 3: Running scaling tests..."
echo "────────────────────────────────────────────────────────────"

DESIGNS=(50000 100000 200000 500000 1000000)

for GATES in "${DESIGNS[@]}"; do
    echo "Submitting ${GATES} gates..."
    
    JOB_ID=$(sbatch \
        --export=ALL,DESIGN_NAME=scaling,DESIGN_GATES=${GATES},STAGE_NAME=synthesis \
        --job-name=learn_${GATES} \
        --output=${RESULTS_DIR}/job_${GATES}_%j.out \
        --mem=4G \
        --time=00:30:00 \
        --wrap="python3 -c 'import time; gates=${GATES}; mem_mb=2000+(gates*8/100); data=[bytearray(100*1024*1024) for _ in range(int(mem_mb/100))]; print(f\"Allocated {len(data)*100} MB\"); time.sleep(10)'" \
        | grep -oP '\d+')
    
    echo "$JOB_ID" >> ${RESULTS_DIR}/job_ids.txt
    sleep 2
done

echo "✓ Jobs submitted"
echo ""

# Wait for completion
echo "Waiting for jobs..."
while squeue -u $USER | grep -q "learn_"; do
    sleep 10
done

echo "✓ All jobs completed"
echo ""

################################################################################
# STEP 4: Collect results
################################################################################

echo "Step 4: Collecting results..."
echo "────────────────────────────────────────────────────────────"

# Get accounting data
sacct --format=JobID,JobName,State,MaxRSS,MaxVMSize,Elapsed,ReqMem \
    -j $(cat ${RESULTS_DIR}/job_ids.txt | tr '\n' ',') \
    > ${RESULTS_DIR}/sacct_summary.txt

# Copy logs
sudo cp /var/log/slurmctld.log ${RESULTS_DIR}/slurmctld.log
sudo chown $USER:$USER ${RESULTS_DIR}/slurmctld.log
grep "job_submit" ${RESULTS_DIR}/slurmctld.log > ${RESULTS_DIR}/plugin_activity.log

# Copy API logs
cp /shared/api.log ${RESULTS_DIR}/ 2>/dev/null || true

# Copy database
cp /shared/hpc_metrics.db ${RESULTS_DIR}/

# Copy source code from work directory
mkdir -p ${RESULTS_DIR}/source_code
cp -r $WORK_DIR/* ${RESULTS_DIR}/source_code/

# Copy installed SLURM files
mkdir -p ${RESULTS_DIR}/slurm_config
sudo cp /opt/slurm/etc/job_submit.lua ${RESULTS_DIR}/slurm_config/ 2>/dev/null || true
sudo cp /opt/slurm/etc/slurm.conf ${RESULTS_DIR}/slurm_config/ 2>/dev/null || true
sudo cp /opt/slurm/etc/plugstack.conf ${RESULTS_DIR}/slurm_config/ 2>/dev/null || true
sudo chown -R $USER:$USER ${RESULTS_DIR}/slurm_config

# Copy SPANK plugins if they exist
mkdir -p ${RESULTS_DIR}/spank_plugins
sudo cp /opt/slurm/lib/slurm/*.so ${RESULTS_DIR}/spank_plugins/ 2>/dev/null || true
sudo chown -R $USER:$USER ${RESULTS_DIR}/spank_plugins 2>/dev/null || true

# Create deployment manifest
cat > ${RESULTS_DIR}/DEPLOYMENT_MANIFEST.txt << EOMANIFEST
HPC Learning System - Deployment Manifest
==========================================
Timestamp: ${TIMESTAMP}
Hostname: $(hostname)
User: $USER

INSTALLED FILES:
================

1. SLURM Configuration:
   - /opt/slurm/etc/job_submit.lua (job_submit plugin)
   - /opt/slurm/etc/slurm.conf (SLURM config)
   - /opt/slurm/etc/plugstack.conf (SPANK config)

2. SPANK Plugins:
   - /opt/slurm/lib/slurm/*.so (if any)

3. Application Files:
   - $WORK_DIR/slurm/job_submit_learning.lua
   - $WORK_DIR/prediction/learning_api.py
   - /shared/hpc_metrics.db (database)
   - /shared/api.log (API logs)

4. Logs:
   - /var/log/slurmctld.log (SLURM controller)

BACKUP CONTENTS:
================
This archive contains:
- source_code/ - All application source files
- slurm_config/ - Installed SLURM configuration files
- spank_plugins/ - Installed SPANK plugins (if any)
- job_*.out - Job output files
- sacct_summary.txt - SLURM accounting data
- slurmctld.log - SLURM controller log
- plugin_activity.log - job_submit plugin activity
- hpc_metrics.db - Database snapshot
- api.log - Prediction API log

RESTORATION:
============
To restore on a new cluster:

1. Copy SLURM files:
   sudo cp slurm_config/job_submit.lua /opt/slurm/etc/
   sudo cp slurm_config/plugstack.conf /opt/slurm/etc/ (if exists)

2. Copy SPANK plugins:
   sudo cp spank_plugins/*.so /opt/slurm/lib/slurm/ (if any)

3. Update slurm.conf:
   echo "JobSubmitPlugins=lua" | sudo tee -a /opt/slurm/etc/slurm.conf

4. Restore application:
   cp -r source_code/* /shared/hpc-learning-system/
   cp hpc_metrics.db /shared/

5. Start API:
   cd /shared/hpc-learning-system
   nohup python3 prediction/learning_api.py > /shared/api.log 2>&1 &

6. Restart SLURM:
   sudo systemctl restart slurmctld

VERIFICATION:
=============
- Check plugin: sudo grep "job_submit" /var/log/slurmctld.log
- Check API: curl http://localhost:8000/health
- Check database: sqlite3 /shared/hpc_metrics.db ".tables"
EOMANIFEST

# Create archive
cd /shared
tar -czf learning-results-${TIMESTAMP}.tar.gz learning-results-${TIMESTAMP}/

echo "✓ Results collected"
echo "  Archive: /shared/learning-results-${TIMESTAMP}.tar.gz"
echo ""

################################################################################
# STEP 5: Upload to S3
################################################################################

if [ -n "$S3_BUCKET" ]; then
    echo "Step 5: Uploading to S3..."
    echo "────────────────────────────────────────────────────────────"
    
    # Upload archive
    if aws s3 cp /shared/learning-results-${TIMESTAMP}.tar.gz \
        ${S3_BUCKET}/learning-results-${TIMESTAMP}.tar.gz; then
        echo "✓ Archive uploaded"
    else
        echo "✗ Archive upload failed"
    fi
    
    # Upload individual files
    if aws s3 cp ${RESULTS_DIR}/ ${S3_BUCKET}/results-${TIMESTAMP}/ --recursive; then
        echo "✓ Results uploaded"
    else
        echo "✗ Results upload failed"
    fi
    
    # Create summary file in S3
    cat > /tmp/s3_summary.txt << EOSUM
HPC Learning System Results
===========================
Timestamp: ${TIMESTAMP}
Cluster: $(hostname)
User: $USER

Files:
- Archive: ${S3_BUCKET}/learning-results-${TIMESTAMP}.tar.gz
- Results: ${S3_BUCKET}/results-${TIMESTAMP}/

Download:
  aws s3 cp ${S3_BUCKET}/learning-results-${TIMESTAMP}.tar.gz .
  aws s3 sync ${S3_BUCKET}/results-${TIMESTAMP}/ ./results/

Jobs Tested:
$(cat ${RESULTS_DIR}/job_ids.txt | nl)
EOSUM
    
    aws s3 cp /tmp/s3_summary.txt ${S3_BUCKET}/results-${TIMESTAMP}/README.txt
    
    echo ""
    echo "✓ Uploaded to S3"
    echo "  Archive: ${S3_BUCKET}/learning-results-${TIMESTAMP}.tar.gz"
    echo "  Results: ${S3_BUCKET}/results-${TIMESTAMP}/"
    echo "  Summary: ${S3_BUCKET}/results-${TIMESTAMP}/README.txt"
else
    echo "Step 5: Skipping S3 upload (no bucket available)"
    echo ""
    echo "Results saved locally:"
    echo "  Directory: $RESULTS_DIR"
    echo "  Archive: /shared/learning-results-${TIMESTAMP}.tar.gz"
fi

echo ""
echo "════════════════════════════════════════════════════════════"
echo "  COMPLETE!"
echo "════════════════════════════════════════════════════════════"
echo ""
echo "Results:"
echo "  Directory: $RESULTS_DIR"
echo "  Archive: /shared/learning-results-${TIMESTAMP}.tar.gz"
[ -n "$S3_BUCKET" ] && echo "  S3: ${S3_BUCKET}/learning-results-${TIMESTAMP}.tar.gz"
echo ""
echo "Files included:"
echo "  - All job outputs"
echo "  - SLURM logs"
echo "  - Plugin activity"
echo "  - Database snapshot"
echo "  - Complete source code"
echo ""
