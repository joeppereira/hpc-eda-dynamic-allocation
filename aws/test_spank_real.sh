#!/bin/bash
# Real SPANK plugin test with auto-detected log paths

set -e

echo "════════════════════════════════════════════════════════════"
echo "  SPANK Dynamic Allocation - Real Test"
echo "════════════════════════════════════════════════════════════"
echo ""

# Function to get log path from slurm.conf
get_log_path() {
    local param=$1
    local default=$2
    local path=$(grep "^${param}=" /opt/slurm/etc/slurm.conf 2>/dev/null | cut -d'=' -f2 | tr -d ' ')
    if [ -n "$path" ]; then
        echo "$path"
    else
        echo "$default"
    fi
}

# Auto-detect log paths
SLURMCTLD_LOG=$(get_log_path "SlurmctldLogFile" "/var/log/slurmctld.log")
SLURMD_LOG=$(get_log_path "SlurmdLogFile" "/var/log/slurmd.log")

echo "Detected log paths:"
echo "  Head node (slurmctld): $SLURMCTLD_LOG"
echo "  Compute node (slurmd): $SLURMD_LOG"
echo ""

# Verify head node log exists
if [ ! -f "$SLURMCTLD_LOG" ]; then
    echo "⚠  Warning: $SLURMCTLD_LOG not found"
    echo "   Checking alternate locations..."
    for alt in /var/log/slurmctld.log /opt/slurm/var/log/slurmctld.log; do
        if [ -f "$alt" ]; then
            SLURMCTLD_LOG="$alt"
            echo "   Found: $SLURMCTLD_LOG"
            break
        fi
    done
fi

echo "Step 1: Verifying SPANK plugin is loaded..."
echo "────────────────────────────────────────────────────────────"

if sudo grep -q "spank_dynamic_alloc" "$SLURMCTLD_LOG" 2>/dev/null; then
    echo "✓ SPANK plugin loaded"
    sudo grep "SPANK Dynamic.*initialized" "$SLURMCTLD_LOG" 2>/dev/null | tail -1
else
    echo "⚠  SPANK plugin not detected in logs"
    echo "   Checking plugstack.conf..."
    if [ -f /opt/slurm/etc/plugstack.conf ]; then
        cat /opt/slurm/etc/plugstack.conf
    else
        echo "   plugstack.conf not found!"
        exit 1
    fi
fi
echo ""

echo "Step 2: Submitting test jobs..."
echo "────────────────────────────────────────────────────────────"

# Test 1: Insufficient allocation
echo "Test 1: 100k gates, 4GB allocated (needs ~10GB)"
JOB1=$(sbatch --gates=100000 --mem=4096M --output=spank_test1_%j.out \
    --wrap="echo 'Job 1: 100k gates with 4GB'; hostname; sleep 10" 2>&1 | grep -oP '\d+$')
echo "  Job ID: $JOB1"

sleep 2

# Test 2: Sufficient allocation
echo "Test 2: 100k gates, 12GB allocated (sufficient)"
JOB2=$(sbatch --gates=100000 --mem=12288M --output=spank_test2_%j.out \
    --wrap="echo 'Job 2: 100k gates with 12GB'; hostname; sleep 10" 2>&1 | grep -oP '\d+$')
echo "  Job ID: $JOB2"

sleep 2

# Test 3: Large design
echo "Test 3: 200k gates, 8GB allocated (needs ~19GB)"
JOB3=$(sbatch --gates=200000 --mem=8192M --output=spank_test3_%j.out \
    --wrap="echo 'Job 3: 200k gates with 8GB'; hostname; sleep 10" 2>&1 | grep -oP '\d+$')
echo "  Job ID: $JOB3"

echo ""
echo "Waiting for jobs to start..."
sleep 5

echo ""
echo "Step 3: Checking job status..."
echo "────────────────────────────────────────────────────────────"
squeue -u $USER -o "%.10i %.9P %.20j %.8u %.2t %.10M %.6D %R"
echo ""

# Wait for at least one job to start running
echo "Waiting for jobs to run..."
for i in {1..30}; do
    RUNNING=$(squeue -h -u $USER -t R | wc -l)
    if [ $RUNNING -gt 0 ]; then
        echo "✓ $RUNNING job(s) running"
        break
    fi
    sleep 2
done
echo ""

echo "Step 4: Fetching SPANK logs from compute nodes..."
echo "────────────────────────────────────────────────────────────"

for JOBID in $JOB1 $JOB2 $JOB3; do
    # Get node where job is/was running
    NODE=$(scontrol show job $JOBID 2>/dev/null | grep -oP 'NodeList=\K[^ ]+' | head -1)
    
    if [ -n "$NODE" ]; then
        echo ""
        echo "Job $JOBID on node $NODE:"
        echo "───────────────────────────────────────"
        
        # Try to fetch SPANK logs from compute node
        if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 $NODE \
            "sudo grep 'SPANK Dynamic' $SLURMD_LOG 2>/dev/null | grep 'Job $JOBID'" 2>/dev/null; then
            echo "✓ SPANK logs retrieved"
        else
            echo "⚠  Could not retrieve logs (job may not have started yet)"
            echo "   Manual check: ssh $NODE \"sudo grep 'SPANK Dynamic' $SLURMD_LOG | grep 'Job $JOBID'\""
        fi
    else
        echo "Job $JOBID: Waiting for node assignment..."
    fi
done

echo ""
echo "Step 5: Waiting for jobs to complete..."
echo "────────────────────────────────────────────────────────────"

# Wait for all jobs to complete
while squeue -h -u $USER 2>/dev/null | grep -q "$JOB1\|$JOB2\|$JOB3"; do
    RUNNING=$(squeue -h -u $USER -t R | wc -l)
    PENDING=$(squeue -h -u $USER -t PD | wc -l)
    echo "[$(date +%H:%M:%S)] Running: $RUNNING, Pending: $PENDING"
    sleep 3
done

echo "✓ All jobs completed"
echo ""

echo "Step 6: Final SPANK log collection..."
echo "════════════════════════════════════════════════════════════"

for JOBID in $JOB1 $JOB2 $JOB3; do
    NODE=$(sacct -j $JOBID --format=NodeList -n | head -1 | tr -d ' ')
    
    if [ -n "$NODE" ] && [ "$NODE" != "None" ]; then
        echo ""
        echo "Job $JOBID (ran on $NODE):"
        echo "────────────────────────────────────────────────────────────"
        
        # Fetch complete SPANK logs for this job
        ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 $NODE \
            "sudo grep 'SPANK Dynamic' $SLURMD_LOG 2>/dev/null | grep 'Job $JOBID'" 2>/dev/null || \
            echo "  No SPANK logs found (check manually)"
        
        # Show job output
        OUTFILE="spank_test${JOBID#$JOB}_%j.out"
        if ls spank_test*_${JOBID}.out 2>/dev/null; then
            echo ""
            echo "  Job output:"
            cat spank_test*_${JOBID}.out 2>/dev/null | sed 's/^/    /'
        fi
    fi
done

echo ""
echo "════════════════════════════════════════════════════════════"
echo "  Summary"
echo "════════════════════════════════════════════════════════════"
echo ""

sacct -j $JOB1,$JOB2,$JOB3 --format=JobID,JobName,NodeList,State,ReqMem,MaxRSS,Elapsed

echo ""
echo "Expected SPANK behavior:"
echo "  Job $JOB1: Should adjust 4GB → ~10GB"
echo "  Job $JOB2: Should approve 12GB (sufficient)"
echo "  Job $JOB3: Should adjust 8GB → ~19GB"
echo ""
echo "To manually check SPANK logs on compute nodes:"
echo "  NODE=\$(sacct -j $JOB1 --format=NodeList -n | head -1 | tr -d ' ')"
echo "  ssh \$NODE \"sudo grep 'SPANK Dynamic' $SLURMD_LOG | grep 'Job $JOB1'\""
echo ""
