#!/bin/bash
# Test real SPANK dynamic allocation plugin

set -e

echo "════════════════════════════════════════════════════════════"
echo "  SPANK Dynamic Allocation - Real Test"
echo "════════════════════════════════════════════════════════════"
echo ""

TEST_DIR="$HOME/spank_real_test_$(date +%s)"
mkdir -p $TEST_DIR/{logs,scripts}
cd $TEST_DIR

echo "Creating test workload script..."
echo "────────────────────────────────────────────────────────────"

# Create a Python script that actually allocates memory
cat > scripts/memory_workload.py << 'EOF'
#!/usr/bin/env python3
import sys
import time
import os

gates = int(sys.argv[1])
print(f"Workload starting: {gates:,} gates")
print(f"PID: {os.getpid()}")
print("")

# Calculate expected memory need (same formula as SPANK)
base_mb = 2000
calculated_mb = base_mb + (gates * 0.08)
buffer_mb = calculated_mb * 0.2
total_mb = calculated_mb + buffer_mb

print(f"Expected memory requirement:")
print(f"  Base: {base_mb} MB")
print(f"  Calculated: {calculated_mb:.0f} MB")
print(f"  With buffer: {total_mb:.0f} MB ({total_mb/1024:.1f} GB)")
print("")

# Try to allocate the calculated amount
print("Allocating memory...")
try:
    # Allocate in 100MB chunks
    chunk_size = 100 * 1024 * 1024
    num_chunks = int(calculated_mb / 100)
    data = []
    
    for i in range(num_chunks):
        chunk = bytearray(chunk_size)
        # Touch the memory to ensure it's actually allocated
        for j in range(0, chunk_size, 4096):
            chunk[j] = i % 256
        data.append(chunk)
        
        if (i + 1) % 10 == 0:
            allocated_gb = (i + 1) * 100 / 1024
            print(f"  Allocated: {allocated_gb:.1f} GB")
    
    print("")
    print(f"✓ SUCCESS: Allocated {calculated_mb/1024:.1f} GB")
    print("  Workload completed without OOM")
    
    # Hold memory for a moment
    time.sleep(5)
    
    # Cleanup
    data.clear()
    print("✓ Memory released")
    
except MemoryError:
    print(f"✗ FAILED: OOM while trying to allocate {calculated_mb/1024:.1f} GB")
    sys.exit(1)
EOF

chmod +x scripts/memory_workload.py

echo "✓ Created memory workload script"
echo ""

echo "Creating test jobs..."
echo "────────────────────────────────────────────────────────────"

# Test A: Under-allocated (should trigger SPANK adjustment)
cat > test_a_insufficient.sh << 'EOFJOB'
#!/bin/bash
#SBATCH --job-name=SPANK_test_insufficient
#SBATCH --output=logs/test_a_%j.out
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=2
#SBATCH --mem=4096M
#SBATCH --time=00:10:00

echo "═══════════════════════════════════════════════════════════"
echo "Test A: Insufficient Initial Allocation"
echo "═══════════════════════════════════════════════════════════"
echo ""
echo "SLURM Allocation: 4 GB"
echo "Design: 100,000 gates"
echo "Expected need: ~10 GB"
echo ""
echo "SPANK should detect shortfall and adjust memory limit"
echo ""

python3 scripts/memory_workload.py 100000
EOFJOB

# Test B: Properly allocated (SPANK should approve)
cat > test_b_sufficient.sh << 'EOFJOB'
#!/bin/bash
#SBATCH --job-name=SPANK_test_sufficient
#SBATCH --output=logs/test_b_%j.out
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=2
#SBATCH --mem=12288M
#SBATCH --time=00:10:00

echo "═══════════════════════════════════════════════════════════"
echo "Test B: Sufficient Initial Allocation"
echo "═══════════════════════════════════════════════════════════"
echo ""
echo "SLURM Allocation: 12 GB"
echo "Design: 100,000 gates"
echo "Expected need: ~10 GB"
echo ""
echo "SPANK should approve current allocation"
echo ""

python3 scripts/memory_workload.py 100000
EOFJOB

# Test C: Large design (stress test)
cat > test_c_large.sh << 'EOFJOB'
#!/bin/bash
#SBATCH --job-name=SPANK_test_large
#SBATCH --output=logs/test_c_%j.out
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=2
#SBATCH --mem=8192M
#SBATCH --time=00:10:00

echo "═══════════════════════════════════════════════════════════"
echo "Test C: Large Design"
echo "═══════════════════════════════════════════════════════════"
echo ""
echo "SLURM Allocation: 8 GB"
echo "Design: 200,000 gates"
echo "Expected need: ~19 GB"
echo ""
echo "SPANK should significantly increase allocation"
echo ""

python3 scripts/memory_workload.py 200000
EOFJOB

chmod +x test_*.sh

echo "✓ Created 3 test jobs"
echo ""

echo "Test Plan:"
echo "────────────────────────────────────────────────────────────"
printf "%-20s %-15s %-15s %-20s\n" "Test" "Initial Alloc" "Required" "Expected Result"
echo "────────────────────────────────────────────────────────────"
printf "%-20s %-15s %-15s %-20s\n" "A: Insufficient" "4 GB" "~10 GB" "SPANK adjusts +6GB"
printf "%-20s %-15s %-15s %-20s\n" "B: Sufficient" "12 GB" "~10 GB" "SPANK approves"
printf "%-20s %-15s %-15s %-20s\n" "C: Large design" "8 GB" "~19 GB" "SPANK adjusts +11GB"
echo "────────────────────────────────────────────────────────────"
echo ""

read -p "Press Enter to submit test jobs..."
echo ""

echo "Submitting jobs..."
echo "────────────────────────────────────────────────────────────"

JOB_A=$(sbatch --gates=100000 test_a_insufficient.sh 2>&1 | grep -oP '\d+$')
echo "  Test A submitted: Job ID $JOB_A"
sleep 1

JOB_B=$(sbatch --gates=100000 test_b_sufficient.sh 2>&1 | grep -oP '\d+$')
echo "  Test B submitted: Job ID $JOB_B"
sleep 1

JOB_C=$(sbatch --gates=200000 test_c_large.sh 2>&1 | grep -oP '\d+$')
echo "  Test C submitted: Job ID $JOB_C"

echo ""
echo "Monitoring execution..."
echo "────────────────────────────────────────────────────────────"

# Monitor jobs
while squeue -h -u $USER 2>/dev/null | grep -q "$JOB_A\|$JOB_B\|$JOB_C"; do
    RUNNING=$(squeue -h -u $USER -t R 2>/dev/null | wc -l)
    PENDING=$(squeue -h -u $USER -t PD 2>/dev/null | wc -l)
    echo "[$(date +%H:%M:%S)] Running: $RUNNING, Pending: $PENDING"
    sleep 5
done

echo "[$(date +%H:%M:%S)] All jobs completed"
echo ""

echo "Results:"
echo "════════════════════════════════════════════════════════════"
echo ""

for test in "A:$JOB_A" "B:$JOB_B" "C:$JOB_C"; do
    IFS=':' read -r name jobid <<< "$test"
    logfile="logs/test_${name,,}_${jobid}.out"
    
    if [ -f "$logfile" ]; then
        echo "Test $name (Job $jobid):"
        echo "────────────────────────────────────────────────────────────"
        
        if grep -q "SUCCESS" "$logfile"; then
            echo "  ✓ SUCCESS - Workload completed"
        elif grep -q "FAILED" "$logfile"; then
            echo "  ✗ FAILED - OOM occurred"
        else
            echo "  ? Unknown status"
        fi
        
        # Show key lines from output
        grep -E "SLURM Allocation|Expected need|SPANK|SUCCESS|FAILED" "$logfile" | sed 's/^/  /'
        echo ""
    fi
done

echo "SPANK Plugin Logs:"
echo "────────────────────────────────────────────────────────────"
echo "Check /var/log/slurm/slurmd.log for SPANK Dynamic messages:"
echo ""
echo "  sudo grep 'SPANK Dynamic' /var/log/slurm/slurmd.log | tail -20"
echo ""

echo "Full job outputs available in: $TEST_DIR/logs/"
echo ""
echo "════════════════════════════════════════════════════════════"
