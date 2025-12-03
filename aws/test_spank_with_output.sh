#!/bin/bash
# Test SPANK plugin with output captured in job files

echo "════════════════════════════════════════════════════════════"
echo "  SPANK Test - Capturing Output in Job Files"
echo "════════════════════════════════════════════════════════════"
echo ""

echo "Creating test job that captures SPANK activity..."
echo ""

# Create a job script that shows memory limits
cat > test_spank_job.sh << 'EOFJOB'
#!/bin/bash
#SBATCH --job-name=spank_test
#SBATCH --output=spank_output_%j.txt
#SBATCH --mem=4096M
#SBATCH --time=00:05:00

echo "════════════════════════════════════════════════════════════"
echo "SPANK Dynamic Allocation Test"
echo "════════════════════════════════════════════════════════════"
echo ""
echo "Job ID: $SLURM_JOB_ID"
echo "Node: $(hostname)"
echo "Requested memory: 4096 MB (4 GB)"
echo "Design: 100,000 gates (should need ~10 GB)"
echo ""

echo "Memory limits at job start:"
ulimit -a | grep -E "memory|virtual"
echo ""

echo "Checking for SPANK plugin on this node:"
ls -la /opt/slurm/lib/slurm/spank_dynamic_alloc.so 2>&1
echo ""

echo "Checking plugstack.conf:"
cat /opt/slurm/etc/plugstack.conf 2>&1
echo ""

echo "Checking slurmd logs for SPANK activity:"
sudo journalctl -u slurmd --no-pager -n 50 | grep -i spank || \
sudo grep "SPANK" /var/log/slurmd.log 2>/dev/null || \
echo "No SPANK logs found"
echo ""

echo "Attempting memory allocation test..."
python3 << 'EOFPYTHON'
import sys
try:
    # Try to allocate 9 GB (what SPANK should have set)
    print("Allocating 9 GB...")
    data = bytearray(9 * 1024 * 1024 * 1024)
    print("✓ Successfully allocated 9 GB")
    print("  SPANK adjustment worked!")
except MemoryError:
    print("✗ Failed to allocate 9 GB")
    print("  SPANK may not have adjusted memory")
EOFPYTHON

echo ""
echo "════════════════════════════════════════════════════════════"
echo "Test complete"
echo "════════════════════════════════════════════════════════════"
EOFJOB

chmod +x test_spank_job.sh

echo "Submitting test job with --gates=100000..."
JOB_ID=$(sbatch --gates=100000 test_spank_job.sh | grep -oP '\d+$')
echo "Job ID: $JOB_ID"
echo ""

echo "Waiting for job to complete..."
while squeue -h -j $JOB_ID 2>/dev/null | grep -q $JOB_ID; do
    sleep 2
done

echo "✓ Job completed"
echo ""

echo "════════════════════════════════════════════════════════════"
echo "Job Output:"
echo "════════════════════════════════════════════════════════════"
cat spank_output_${JOB_ID}.txt

echo ""
echo "════════════════════════════════════════════════════════════"
echo ""
echo "Analysis:"
echo "  - If memory allocation succeeded: SPANK worked"
echo "  - If memory allocation failed: SPANK not active on compute nodes"
echo ""
echo "Next steps if SPANK not working:"
echo "  1. Check if /opt/slurm is NFS-mounted on compute nodes"
echo "  2. Verify compute nodes can access the .so file"
echo "  3. May need to add SPANK setup to compute node bootstrap"
echo ""
