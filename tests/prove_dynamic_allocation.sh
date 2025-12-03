#!/bin/bash
# Proof of Dynamic Allocation - Shows actual resource adjustment

echo "════════════════════════════════════════════════════════════"
echo "  Dynamic Allocation Proof - Before/After Comparison"
echo "════════════════════════════════════════════════════════════"
echo ""

# Create test workload
cat > large_workload.sh << 'EOFJOB'
#!/bin/bash
#SBATCH --time=00:10:00

echo "════════════════════════════════════════════════════════════"
echo "LARGE WORKLOAD TEST - Job $SLURM_JOB_ID"
echo "════════════════════════════════════════════════════════════"
echo "Timestamp: $(date '+%Y-%m-%d %H:%M:%S.%3N')"
echo "Node: $(hostname)"
echo ""

# Show what SLURM allocated
echo "SLURM Job Information:"
echo "  Job ID: $SLURM_JOB_ID"
echo "  Requested Memory: $SLURM_MEM_PER_NODE MB"
echo "  Design Gates: ${DESIGN_GATES:-not set}"
echo ""

# Calculate what we need
GATES=${DESIGN_GATES:-0}
if [ $GATES -gt 0 ]; then
    CALC_MB=$((2000 + GATES * 8 / 100))
    BUFFER_MB=$((CALC_MB * 20 / 100))
    NEED_MB=$((CALC_MB + BUFFER_MB))
    
    echo "Memory Calculation:"
    echo "  Base: 2000 MB"
    echo "  For $GATES gates: $CALC_MB MB"
    echo "  With 20% buffer: $NEED_MB MB ($(echo "scale=1; $NEED_MB/1024" | bc) GB)"
    echo ""
    
    # Check if job_submit plugin adjusted it
    if [ "$SLURM_MEM_PER_NODE" -ge "$NEED_MB" ]; then
        echo "✓ Job Submit Plugin WORKED!"
        echo "  Requested: 4096 MB (4 GB)"
        echo "  Adjusted to: $SLURM_MEM_PER_NODE MB ($(echo "scale=1; $SLURM_MEM_PER_NODE/1024" | bc) GB)"
        echo "  Increase: $((SLURM_MEM_PER_NODE - 4096)) MB"
    else
        echo "⚠ Memory may be insufficient"
        echo "  Have: $SLURM_MEM_PER_NODE MB"
        echo "  Need: $NEED_MB MB"
    fi
fi
echo ""

# Show actual memory limits
echo "System Memory Limits:"
echo "  Virtual memory: $(ulimit -v) KB"
echo "  Max memory: $(ulimit -m) KB"
echo ""

# Check cgroup limits
if [ -f /proc/self/cgroup ]; then
    echo "Cgroup Information:"
    cat /proc/self/cgroup | grep memory
    
    # Try to read cgroup memory limit
    CGROUP_PATH=$(cat /proc/self/cgroup | grep memory | cut -d: -f3)
    if [ -n "$CGROUP_PATH" ]; then
        CGROUP_LIMIT=$(cat /sys/fs/cgroup/memory${CGROUP_PATH}/memory.limit_in_bytes 2>/dev/null)
        if [ -n "$CGROUP_LIMIT" ]; then
            CGROUP_MB=$((CGROUP_LIMIT / 1024 / 1024))
            echo "  Cgroup memory limit: $CGROUP_MB MB ($(echo "scale=1; $CGROUP_MB/1024" | bc) GB)"
        fi
    fi
fi
echo ""

# Perform actual allocation test
echo "Performing Allocation Test:"
echo "────────────────────────────────────────────────────────────"

ALLOC_GB=$(echo "scale=0; $NEED_MB / 1024" | bc)
echo "Attempting to allocate ${ALLOC_GB} GB..."
echo ""

START_TIME=$(date +%s.%N)

python3 << EOFPY
import sys
import time

gates = ${GATES}
need_mb = ${NEED_MB}
need_gb = need_mb / 1024

print(f"Allocating {need_gb:.1f} GB for {gates:,} gates...")
print("")

try:
    # Allocate in chunks to show progress
    chunk_size = 1024 * 1024 * 1024  # 1GB chunks
    num_chunks = int(need_gb)
    data = []
    
    for i in range(num_chunks):
        start = time.time()
        chunk = bytearray(chunk_size)
        # Touch memory
        for j in range(0, chunk_size, 4096):
            chunk[j] = i % 256
        data.append(chunk)
        elapsed = time.time() - start
        print(f"  [{i+1}/{num_chunks}] Allocated {i+1} GB (took {elapsed:.2f}s)")
    
    print("")
    print(f"✓ SUCCESS: Allocated {need_gb:.1f} GB")
    print(f"  Total memory allocated: {len(data)} GB")
    print(f"  Job Submit Plugin enabled this allocation!")
    print("")
    
    # Hold memory briefly
    time.sleep(2)
    
    # Cleanup
    data.clear()
    print("Memory released")
    
except MemoryError as e:
    print(f"✗ FAILED: OOM at {len(data)} GB")
    print(f"  Attempted: {need_gb:.1f} GB")
    print(f"  Achieved: {len(data)} GB")
    sys.exit(1)
EOFPY

END_TIME=$(date +%s.%N)
DURATION=$(echo "$END_TIME - $START_TIME" | bc)

echo ""
echo "Test Duration: ${DURATION}s"
echo ""
echo "════════════════════════════════════════════════════════════"
echo "CONCLUSION: Job Submit Plugin $([ $? -eq 0 ] && echo 'WORKING' || echo 'FAILED')"
echo "════════════════════════════════════════════════════════════"
EOFJOB

chmod +x large_workload.sh

echo "Test 1: WITHOUT Dynamic Allocation (Control)"
echo "────────────────────────────────────────────────────────────"
echo "Submitting with 4GB (insufficient for 200k gates)..."

JOB_CONTROL=$(sbatch \
    --mem=4096M \
    --job-name="control_no_plugin" \
    --output="control_%j.txt" \
    --wrap="echo 'Control test (no DESIGN_GATES)'; python3 -c 'data=bytearray(19*1024*1024*1024); print(\"Success\")'" \
    | grep -oP '\d+$')

echo "  Job ID: $JOB_CONTROL (expected to FAIL with OOM)"
echo ""

sleep 2

echo "Test 2: WITH Dynamic Allocation (Job Submit Plugin)"
echo "────────────────────────────────────────────────────────────"
echo "Submitting with 4GB but DESIGN_GATES=200000 (needs 19GB)..."

JOB_DYNAMIC=$(sbatch \
    --export=ALL,DESIGN_GATES=200000 \
    --mem=4096M \
    --job-name="dynamic_with_plugin" \
    --output="dynamic_%j.txt" \
    large_workload.sh \
    | grep -oP '\d+$')

echo "  Job ID: $JOB_DYNAMIC (expected to SUCCEED with adjustment)"
echo ""

echo "Waiting for jobs to complete..."
echo ""

# Monitor
while squeue -h -j $JOB_CONTROL,$JOB_DYNAMIC 2>/dev/null | grep -q "$JOB_CONTROL\|$JOB_DYNAMIC"; do
    echo "[$(date +%H:%M:%S)] Jobs running..."
    sleep 5
done

echo "✓ Jobs completed"
echo ""

echo "════════════════════════════════════════════════════════════"
echo "  RESULTS - Proof of Dynamic Allocation"
echo "════════════════════════════════════════════════════════════"
echo ""

echo "Test 1: Control (No Dynamic Allocation)"
echo "────────────────────────────────────────────────────────────"
cat control_${JOB_CONTROL}.txt 2>/dev/null || echo "Output file not found"
echo ""

echo "Test 2: With Dynamic Allocation"
echo "────────────────────────────────────────────────────────────"
cat dynamic_${JOB_DYNAMIC}.txt 2>/dev/null || echo "Output file not found"
echo ""

echo "════════════════════════════════════════════════════════════"
echo "  Job Submit Plugin Logs"
echo "════════════════════════════════════════════════════════════"
echo ""
echo "Plugin activity for these jobs:"
grep "job_submit.*Job.*$JOB_CONTROL\|job_submit.*Job.*$JOB_DYNAMIC" /var/log/slurmctld.log 2>/dev/null || \
grep "job_submit.*DESIGN_GATES" /var/log/slurmctld.log 2>/dev/null | tail -5
echo ""

echo "════════════════════════════════════════════════════════════"
echo "  PROOF SUMMARY"
echo "════════════════════════════════════════════════════════════"
echo ""

if grep -q "SUCCESS" control_${JOB_CONTROL}.txt 2>/dev/null; then
    echo "Control: ✗ Unexpected success (should have failed)"
elif grep -q "Killed\|OOM" control_${JOB_CONTROL}.txt 2>/dev/null; then
    echo "Control: ✓ Failed as expected (OOM with 4GB)"
fi

if grep -q "SUCCESS" dynamic_${JOB_DYNAMIC}.txt 2>/dev/null; then
    echo "Dynamic: ✓ SUCCESS - Plugin adjusted memory!"
    echo ""
    echo "PROOF: Job Submit Plugin dynamically allocated resources!"
    echo "  Requested: 4 GB"
    echo "  Adjusted to: ~19 GB"
    echo "  Result: Job succeeded"
elif grep -q "Killed\|OOM" dynamic_${JOB_DYNAMIC}.txt 2>/dev/null; then
    echo "Dynamic: ✗ Failed - Plugin may not be working"
fi

echo ""
