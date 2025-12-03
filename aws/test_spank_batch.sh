#!/bin/bash
# Test SPANK with a proper batch script (not --wrap)

echo "Creating batch script for SPANK test..."

cat > spank_batch_test.slurm << 'EOFJOB'
#!/bin/bash
#SBATCH --job-name=spank_batch
#SBATCH --output=spank_batch_%j.txt
#SBATCH --mem=4096M
#SBATCH --time=00:05:00

echo "════════════════════════════════════════════════════════════"
echo "SPANK Batch Script Test"
echo "════════════════════════════════════════════════════════════"
echo "Job ID: $SLURM_JOB_ID"
echo "Node: $(hostname)"
echo "DESIGN_GATES: ${DESIGN_GATES:-not set}"
echo ""

echo "Checking SPANK logs on this node:"
journalctl -u slurmd --no-pager -n 50 | grep "Job $SLURM_JOB_ID" | grep "SPANK Dynamic" || echo "No SPANK messages for this job"
echo ""

echo "Attempting 9GB allocation..."
python3 << 'EOFPY'
try:
    data = bytearray(9 * 1024 * 1024 * 1024)
    print("✓ SUCCESS: Allocated 9GB - SPANK worked!")
except MemoryError:
    print("✗ FAILED: OOM - SPANK did not adjust memory")
EOFPY

echo ""
echo "Test complete"
EOFJOB

chmod +x spank_batch_test.slurm

echo "Submitting with DESIGN_GATES environment variable..."
JOB_ID=$(sbatch --export=ALL,DESIGN_GATES=100000 spank_batch_test.slurm | grep -oP '\d+$')
echo "Job ID: $JOB_ID"
echo ""

echo "Waiting for job to complete..."
while squeue -h -j $JOB_ID 2>/dev/null | grep -q $JOB_ID; do
    sleep 2
done

echo "✓ Job completed"
echo ""
echo "════════════════════════════════════════════════════════════"
echo "Results:"
echo "════════════════════════════════════════════════════════════"
cat spank_batch_${JOB_ID}.txt
echo ""
