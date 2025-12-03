#!/bin/bash
# Quick SPANK plugin test

echo "════════════════════════════════════════════════════════════"
echo "  SPANK Dynamic Allocation - Quick Test"
echo "════════════════════════════════════════════════════════════"
echo ""

# Test 1: Small design with insufficient allocation
echo "Test 1: Submitting job with insufficient memory..."
echo "  Design: 100,000 gates (needs ~10 GB)"
echo "  Allocated: 4 GB"
echo "  Expected: SPANK will adjust to 10 GB"
echo ""

JOB1=$(sbatch --gates=100000 --mem=4096M --wrap="echo 'Job with 100k gates'; sleep 15" 2>&1 | grep -oP '\d+$')
echo "  Submitted Job ID: $JOB1"
echo ""

# Test 2: Large design with insufficient allocation
echo "Test 2: Submitting job with large design..."
echo "  Design: 200,000 gates (needs ~19 GB)"
echo "  Allocated: 8 GB"
echo "  Expected: SPANK will adjust to 19 GB"
echo ""

JOB2=$(sbatch --gates=200000 --mem=8192M --wrap="echo 'Job with 200k gates'; sleep 15" 2>&1 | grep -oP '\d+$')
echo "  Submitted Job ID: $JOB2"
echo ""

# Test 3: Properly allocated (SPANK should approve)
echo "Test 3: Submitting job with sufficient memory..."
echo "  Design: 100,000 gates (needs ~10 GB)"
echo "  Allocated: 12 GB"
echo "  Expected: SPANK will approve"
echo ""

JOB3=$(sbatch --gates=100000 --mem=12288M --wrap="echo 'Job with sufficient memory'; sleep 15" 2>&1 | grep -oP '\d+$')
echo "  Submitted Job ID: $JOB3"
echo ""

echo "Waiting for jobs to start..."
sleep 5

echo ""
echo "════════════════════════════════════════════════════════════"
echo "  Finding SPANK Logs"
echo "════════════════════════════════════════════════════════════"
echo ""

# Find SLURM log directory
SLURM_LOG_DIR=""
for dir in /var/log/slurm /opt/slurm/var/log /var/log; do
    if [ -d "$dir" ]; then
        SLURM_LOG_DIR="$dir"
        break
    fi
done

echo "SLURM log directory: $SLURM_LOG_DIR"
echo ""

# Wait for jobs to complete
echo "Waiting for jobs to complete..."
while squeue -h -u $USER 2>/dev/null | grep -q "$JOB1\|$JOB2\|$JOB3"; do
    sleep 2
done
echo "✓ Jobs completed"
echo ""

echo "════════════════════════════════════════════════════════════"
echo "  Job Output"
echo "════════════════════════════════════════════════════════════"
echo ""

# Check job output files
for jobid in $JOB1 $JOB2 $JOB3; do
    outfile="slurm-${jobid}.out"
    if [ -f "$outfile" ]; then
        echo "Job $jobid output:"
        cat "$outfile"
        echo ""
    fi
done

echo "════════════════════════════════════════════════════════════"
echo "  SPANK Plugin Logs"
echo "════════════════════════════════════════════════════════════"
echo ""

# Check slurmctld log (head node)
if [ -f "$SLURM_LOG_DIR/slurmctld.log" ]; then
    echo "Head node (slurmctld) SPANK activity:"
    sudo grep "SPANK Dynamic" "$SLURM_LOG_DIR/slurmctld.log" 2>/dev/null | tail -10
    echo ""
fi

# Check for slurmd logs (compute nodes)
if [ -f "$SLURM_LOG_DIR/slurmd.log" ]; then
    echo "Compute node (slurmd) SPANK activity:"
    sudo grep "SPANK Dynamic" "$SLURM_LOG_DIR/slurmd.log" 2>/dev/null | tail -20
    echo ""
else
    echo "Note: slurmd.log is on compute nodes, not head node"
    echo ""
    echo "To check SPANK activity on compute nodes:"
    echo "  1. Find compute node: scontrol show job $JOB1 | grep NodeList"
    echo "  2. SSH to compute node"
    echo "  3. Check: sudo grep 'SPANK Dynamic' /var/log/slurm/slurmd.log"
    echo ""
fi

echo "════════════════════════════════════════════════════════════"
echo ""
echo "To see SPANK logs on compute nodes:"
echo "  # Get compute node name"
echo "  NODE=\$(scontrol show job $JOB1 | grep -oP 'NodeList=\K[^ ]+')"
echo "  # SSH to compute node"
echo "  ssh \$NODE"
echo "  # Check SPANK logs"
echo "  sudo grep 'SPANK Dynamic' /var/log/slurm/slurmd.log"
echo ""
