#!/bin/bash
# Clean proof: Show SLURM adjusts --mem based on DESIGN_GATES

echo "════════════════════════════════════════════════════════════"
echo "  Dynamic Allocation Proof - SLURM Memory Adjustment"
echo "════════════════════════════════════════════════════════════"
echo ""
echo "This test proves the job_submit plugin adjusts memory limits"
echo "WITHOUT artificially allocating memory."
echo ""

# Test 1: Submit WITHOUT DESIGN_GATES
echo "Test 1: Control (no DESIGN_GATES)"
echo "────────────────────────────────────────────────────────────"
echo "Submitting with --mem=4096M, no DESIGN_GATES..."

JOB1=$(sbatch \
    --mem=4096M \
    --job-name="control" \
    --output="control_%j.txt" \
    --wrap='echo "Job ID: $SLURM_JOB_ID"; echo "Allocated Memory: $SLURM_MEM_PER_NODE MB"; echo "Design Gates: ${DESIGN_GATES:-not set}"' \
    | grep -oP '\d+')

echo "  Job ID: $JOB1"
echo ""

sleep 2

# Test 2: Submit WITH DESIGN_GATES
echo "Test 2: With DESIGN_GATES=200000"
echo "────────────────────────────────────────────────────────────"
echo "Submitting with --mem=4096M, DESIGN_GATES=200000..."
echo "(Plugin should adjust to ~19GB)"

JOB2=$(sbatch \
    --export=ALL,DESIGN_GATES=200000 \
    --mem=4096M \
    --job-name="dynamic" \
    --output="dynamic_%j.txt" \
    --wrap='echo "Job ID: $SLURM_JOB_ID"; echo "Allocated Memory: $SLURM_MEM_PER_NODE MB"; echo "Design Gates: ${DESIGN_GATES:-not set}"; echo ""; echo "Expected: ~19456 MB (19 GB)"; echo "Calculation: 2000 + (200000 * 8 / 100) * 1.2 = 19456 MB"' \
    | grep -oP '\d+')

echo "  Job ID: $JOB2"
echo ""

# Wait for completion
echo "Waiting for jobs to complete..."
while squeue -h -j $JOB1,$JOB2 2>/dev/null | grep -q "$JOB1\|$JOB2"; do
    sleep 2
done
echo "✓ Jobs completed"
echo ""

# Show results
echo "════════════════════════════════════════════════════════════"
echo "  RESULTS"
echo "════════════════════════════════════════════════════════════"
echo ""

echo "Test 1: Control (no plugin adjustment)"
echo "────────────────────────────────────────────────────────────"
cat control_${JOB1}.txt
echo ""

echo "Test 2: With plugin adjustment"
echo "────────────────────────────────────────────────────────────"
cat dynamic_${JOB2}.txt
echo ""

# Extract memory values
MEM1=$(grep "Allocated Memory:" control_${JOB1}.txt | grep -oP '\d+')
MEM2=$(grep "Allocated Memory:" dynamic_${JOB2}.txt | grep -oP '\d+')

echo "════════════════════════════════════════════════════════════"
echo "  PROOF"
echo "════════════════════════════════════════════════════════════"
echo ""
echo "Control Job:  $MEM1 MB (4 GB) - No adjustment"
echo "Dynamic Job:  $MEM2 MB (~19 GB) - Plugin adjusted!"
echo ""

if [ "$MEM2" -gt "$MEM1" ]; then
    INCREASE=$((MEM2 - MEM1))
    echo "✓ PROOF: Plugin increased memory by $INCREASE MB"
    echo ""
    echo "The job_submit plugin dynamically adjusted --mem based on"
    echo "DESIGN_GATES environment variable BEFORE the job ran."
    echo ""
    echo "SLURM enforces this limit via cgroups. The application"
    echo "(OpenROAD) can now safely use up to $MEM2 MB."
else
    echo "✗ Plugin may not be working - no memory increase detected"
fi

echo ""
echo "════════════════════════════════════════════════════════════"
echo "  Plugin Logs"
echo "════════════════════════════════════════════════════════════"
echo ""
grep "job_submit.*Job.*$JOB2" /var/log/slurmctld.log 2>/dev/null | tail -3 || \
    echo "Check /var/log/slurmctld.log for job_submit plugin activity"
echo ""
