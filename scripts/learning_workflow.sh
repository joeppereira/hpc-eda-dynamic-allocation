#!/bin/bash
# Learning-based resource allocation workflow
# Demonstrates how the system learns from job executions

set -e

echo "════════════════════════════════════════════════════════════"
echo "  Learning-Based Resource Allocation Workflow"
echo "════════════════════════════════════════════════════════════"
echo ""
echo "This demonstrates:"
echo "  1. First run: No history → Use defaults → Monitor actual usage"
echo "  2. Store metrics in database"
echo "  3. Train/update ML model"
echo "  4. Second run: Query history → Predict → Adjust resources"
echo ""

# Configuration
DESIGN_NAME="aes_cipher"
DESIGN_GATES=50000
STAGE="synthesis"

# Start prediction API
echo "Step 1: Starting Prediction API"
echo "────────────────────────────────────────────────────────────"
python3 prediction/learning_api.py &
API_PID=$!
sleep 3

# Check API health
if curl -s http://localhost:8000/health | grep -q "healthy"; then
    echo "✓ API is running"
else
    echo "✗ API failed to start"
    kill $API_PID 2>/dev/null
    exit 1
fi

# Check initial stats
echo ""
echo "Initial Database Stats:"
curl -s http://localhost:8000/stats | python3 -m json.tool
echo ""

# ============================================================================
# FIRST RUN - No historical data
# ============================================================================
echo ""
echo "════════════════════════════════════════════════════════════"
echo "  FIRST RUN - Learning Phase"
echo "════════════════════════════════════════════════════════════"
echo ""

echo "Querying prediction API (should return defaults)..."
PREDICTION=$(curl -s "http://localhost:8000/predict?design_name=${DESIGN_NAME}&gates=${DESIGN_GATES}&stage=${STAGE}")
echo "$PREDICTION" | python3 -m json.tool
echo ""

# Extract predicted memory
PRED_MEMORY=$(echo "$PREDICTION" | python3 -c "import sys, json; print(json.load(sys.stdin)['memory_gb'])")
PRED_CORES=$(echo "$PREDICTION" | python3 -c "import sys, json; print(json.load(sys.stdin)['cpu_cores'])")
CONFIDENCE=$(echo "$PREDICTION" | python3 -c "import sys, json; print(json.load(sys.stdin)['confidence'])")

echo "Prediction:"
echo "  Memory: ${PRED_MEMORY} GB"
echo "  Cores: ${PRED_CORES}"
echo "  Confidence: ${CONFIDENCE}"
echo ""

if [ "$CONFIDENCE" = "low" ]; then
    echo "✓ As expected: Low confidence (no historical data)"
else
    echo "⚠ Unexpected: Should have low confidence on first run"
fi
echo ""

# Submit job with monitoring
echo "Submitting job with monitoring..."
echo "  Design: ${DESIGN_NAME}"
echo "  Gates: ${DESIGN_GATES}"
echo "  Stage: ${STAGE}"
echo ""

# Create test job script
cat > /tmp/test_job_${DESIGN_NAME}.sh << 'EOF'
#!/bin/bash
#SBATCH --job-name=learning_test_1
#SBATCH --output=learning_test_1_%j.txt
#SBATCH --time=00:10:00

echo "════════════════════════════════════════════════════════════"
echo "JOB 1: First Run (Learning Phase)"
echo "════════════════════════════════════════════════════════════"
echo "Job ID: $SLURM_JOB_ID"
echo "Design: $DESIGN_NAME"
echo "Gates: $DESIGN_GATES"
echo "Stage: $STAGE_NAME"
echo "Allocated Memory: $SLURM_MEM_PER_NODE MB"
echo "Allocated Cores: $SLURM_CPUS_ON_NODE"
echo ""

# Simulate OpenROAD work
echo "Running synthesis..."
python3 << 'EOPY'
import time
import psutil
import os

# Simulate memory usage based on design size
gates = int(os.environ.get('DESIGN_GATES', 50000))
memory_mb = 2000 + (gates * 8 / 100)  # Formula: 2GB base + 8MB per 100 gates

print(f"Simulating synthesis for {gates:,} gates")
print(f"Expected memory usage: {memory_mb:.0f} MB ({memory_mb/1024:.1f} GB)")
print("")

# Allocate memory gradually
data = []
chunk_size = 100 * 1024 * 1024  # 100MB chunks
target_bytes = int(memory_mb * 1024 * 1024)
allocated = 0

while allocated < target_bytes:
    chunk = bytearray(chunk_size)
    # Touch memory
    for i in range(0, len(chunk), 4096):
        chunk[i] = 1
    data.append(chunk)
    allocated += chunk_size
    
    if allocated % (500 * 1024 * 1024) == 0:  # Every 500MB
        print(f"  Allocated: {allocated / 1024 / 1024:.0f} MB")

print(f"✓ Peak memory: {allocated / 1024 / 1024:.0f} MB")
print("")

# Simulate computation
print("Computing...")
time.sleep(5)

print("✓ Synthesis complete")
EOPY

echo ""
echo "════════════════════════════════════════════════════════════"
echo "Job 1 Complete - Metrics will be collected"
echo "════════════════════════════════════════════════════════════"
EOF

# Submit job
JOB1=$(sbatch \
    --export=ALL,DESIGN_NAME=${DESIGN_NAME},DESIGN_GATES=${DESIGN_GATES},STAGE_NAME=${STAGE} \
    --mem=${PRED_MEMORY}G \
    --cpus-per-task=${PRED_CORES} \
    /tmp/test_job_${DESIGN_NAME}.sh \
    | grep -oP '\d+')

echo "Job submitted: $JOB1"
echo "Waiting for completion..."

# Wait for job
while squeue -h -j $JOB1 2>/dev/null | grep -q "$JOB1"; do
    sleep 2
done

echo "✓ Job completed"
echo ""

# Show job output
echo "Job Output:"
echo "────────────────────────────────────────────────────────────"
cat learning_test_1_${JOB1}.txt
echo ""

# ============================================================================
# COLLECT METRICS
# ============================================================================
echo ""
echo "════════════════════════════════════════════════════════════"
echo "  COLLECTING METRICS"
echo "════════════════════════════════════════════════════════════"
echo ""

# Get actual resource usage from SLURM accounting
echo "Querying SLURM accounting..."
sacct -j $JOB1 --format=JobID,MaxRSS,MaxVMSize,AveCPU,Elapsed -P

# Extract actual memory usage
ACTUAL_MEMORY=$(sacct -j $JOB1 --format=MaxRSS -P -n | head -1 | sed 's/K$//' | awk '{print $1/1024/1024}')

echo ""
echo "Actual Resource Usage:"
echo "  Memory: ${ACTUAL_MEMORY} GB"
echo ""

# Store in database (simulate)
echo "Storing metrics in database..."
python3 << EOPY
import sqlite3
from datetime import datetime

# Connect to database
conn = sqlite3.connect('data/metrics.db')
cursor = conn.cursor()

# Insert job record
cursor.execute("""
INSERT INTO jobs (job_name, tool_name, submit_time, status, slurm_memory_gb)
VALUES (?, ?, ?, ?, ?)
""", ('${DESIGN_NAME}', 'openroad', datetime.now(), 'completed', ${ACTUAL_MEMORY}))

job_id = cursor.lastrowid

# Insert design features
cursor.execute("""
INSERT INTO design_features (job_id, cell_count, net_count, die_area_um2, clock_freq_mhz)
VALUES (?, ?, ?, ?, ?)
""", (job_id, ${DESIGN_GATES}, int(${DESIGN_GATES} * 0.9), ${DESIGN_GATES} * 20, 100))

# Insert stage
cursor.execute("""
INSERT INTO job_stages (job_id, stage_name, stage_order, duration_sec)
VALUES (?, ?, ?, ?)
""", (job_id, '${STAGE}', 1, 300))

stage_id = cursor.lastrowid

# Insert stage resources
cursor.execute("""
INSERT INTO stage_resources (stage_id, memory_peak_gb, cpu_cores_used)
VALUES (?, ?, ?)
""", (stage_id, ${ACTUAL_MEMORY}, ${PRED_CORES}))

conn.commit()
conn.close()

print("✓ Metrics stored in database")
EOPY

echo ""

# ============================================================================
# TRAIN MODEL
# ============================================================================
echo ""
echo "════════════════════════════════════════════════════════════"
echo "  TRAINING MODEL"
echo "════════════════════════════════════════════════════════════"
echo ""

echo "Training ML model with new data..."
python3 scripts/train_model.py
echo ""

# Restart API to reload model
echo "Reloading prediction API..."
kill $API_PID
sleep 2
python3 prediction/learning_api.py &
API_PID=$!
sleep 3
echo "✓ API reloaded"
echo ""

# ============================================================================
# SECOND RUN - With historical data
# ============================================================================
echo ""
echo "════════════════════════════════════════════════════════════"
echo "  SECOND RUN - Prediction Phase"
echo "════════════════════════════════════════════════════════════"
echo ""

echo "Querying prediction API (should use historical data)..."
PREDICTION2=$(curl -s "http://localhost:8000/predict?design_name=${DESIGN_NAME}&gates=${DESIGN_GATES}&stage=${STAGE}")
echo "$PREDICTION2" | python3 -m json.tool
echo ""

PRED_MEMORY2=$(echo "$PREDICTION2" | python3 -c "import sys, json; print(json.load(sys.stdin)['memory_gb'])")
CONFIDENCE2=$(echo "$PREDICTION2" | python3 -c "import sys, json; print(json.load(sys.stdin)['confidence'])")
SOURCE2=$(echo "$PREDICTION2" | python3 -c "import sys, json; print(json.load(sys.stdin)['source'])")

echo "New Prediction:"
echo "  Memory: ${PRED_MEMORY2} GB (was ${PRED_MEMORY} GB)"
echo "  Confidence: ${CONFIDENCE2} (was ${CONFIDENCE})"
echo "  Source: ${SOURCE2}"
echo ""

if [ "$CONFIDENCE2" != "low" ]; then
    echo "✓ SUCCESS: System learned from first run!"
    echo "  Confidence improved: ${CONFIDENCE} → ${CONFIDENCE2}"
    echo "  Using: ${SOURCE2}"
else
    echo "⚠ System did not learn (may need more data)"
fi

echo ""
echo "════════════════════════════════════════════════════════════"
echo "  LEARNING WORKFLOW COMPLETE"
echo "════════════════════════════════════════════════════════════"
echo ""
echo "Summary:"
echo "  1. First run used defaults (no history)"
echo "  2. Actual usage was collected and stored"
echo "  3. Model was trained/updated"
echo "  4. Second run used learned prediction"
echo ""
echo "The system will continue to improve with more job executions!"
echo ""

# Cleanup
kill $API_PID 2>/dev/null
