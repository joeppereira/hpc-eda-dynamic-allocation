#!/bin/bash
# Comprehensive Dynamic Allocation Test Suite
# Tests various design sizes, configurations, and resource requirements

set -e

echo "════════════════════════════════════════════════════════════"
echo "  Comprehensive Dynamic Allocation Test Suite"
echo "════════════════════════════════════════════════════════════"
echo ""

TEST_DIR="comprehensive_test_$(date +%s)"
mkdir -p $TEST_DIR
cd $TEST_DIR

# Test scenarios: name:gates:initial_mem_mb:expected_mem_mb:config
SCENARIOS=(
    "tiny:10000:1024:2400:low_power"
    "small:50000:2048:6000:balanced"
    "medium:100000:4096:9600:high_freq"
    "large:200000:8192:19200:high_density"
    "xlarge:500000:16384:48000:max_performance"
    "under_allocated:150000:4096:14400:balanced"
    "over_allocated:50000:16384:6000:balanced"
    "exact_match:100000:9600:9600:balanced"
)

echo "Test Matrix:"
echo "────────────────────────────────────────────────────────────"
printf "%-20s %-10s %-12s %-12s %-15s\n" "Scenario" "Gates" "Initial" "Expected" "Config"
echo "────────────────────────────────────────────────────────────"

for scenario in "${SCENARIOS[@]}"; do
    IFS=':' read -r name gates initial expected config <<< "$scenario"
    printf "%-20s %-10s %-12s %-12s %-15s\n" "$name" "$gates" "${initial}MB" "${expected}MB" "$config"
done

echo "────────────────────────────────────────────────────────────"
echo ""

# Create test workload script
cat > workload.sh << 'EOFWORK'
#!/bin/bash
#SBATCH --time=00:05:00

echo "═══════════════════════════════════════════════════════════"
echo "Dynamic Allocation Test - Job $SLURM_JOB_ID"
echo "═══════════════════════════════════════════════════════════"
echo ""
echo "Timestamp: $(date '+%Y-%m-%d %H:%M:%S')"
echo "Node: $(hostname)"
echo "Job ID: $SLURM_JOB_ID"
echo ""

# Design parameters
GATES=${DESIGN_GATES:-0}
CONFIG=${DESIGN_CONFIG:-unknown}
INITIAL_MEM=${SLURM_MEM_PER_NODE:-0}

echo "Design Parameters:"
echo "  Gates: $GATES"
echo "  Configuration: $CONFIG"
echo "  Initial Memory Request: ${INITIAL_MEM}MB"
echo ""

# Calculate expected memory
BASE_MB=2000
CALCULATED_MB=$((BASE_MB + GATES * 8 / 100))
BUFFER_MB=$((CALCULATED_MB * 20 / 100))
EXPECTED_MB=$((CALCULATED_MB + BUFFER_MB))

echo "Memory Prediction:"
echo "  Base: ${BASE_MB}MB"
echo "  Calculated: ${CALCULATED_MB}MB (${GATES} gates × 0.08MB)"
echo "  Buffer (20%): ${BUFFER_MB}MB"
echo "  Total Expected: ${EXPECTED_MB}MB ($(echo "scale=1; $EXPECTED_MB/1024" | bc)GB)"
echo ""

# Configuration-specific adjustments
case $CONFIG in
    low_power)
        echo "Configuration: Low Power"
        echo "  - Reduced frequency: 1.0 GHz"
        echo "  - Power target: 50W"
        echo "  - Memory efficiency: +10%"
        ADJUSTED_MB=$((EXPECTED_MB * 110 / 100))
        ;;
    high_freq)
        echo "Configuration: High Frequency"
        echo "  - Increased frequency: 3.0 GHz"
        echo "  - Power target: 150W"
        echo "  - Memory overhead: +15%"
        ADJUSTED_MB=$((EXPECTED_MB * 115 / 100))
        ;;
    high_density)
        echo "Configuration: High Density"
        echo "  - Reduced area: 70%"
        echo "  - Increased utilization: 85%"
        echo "  - Memory overhead: +20%"
        ADJUSTED_MB=$((EXPECTED_MB * 120 / 100))
        ;;
    max_performance)
        echo "Configuration: Maximum Performance"
        echo "  - Max frequency: 4.0 GHz"
        echo "  - Max power: 200W"
        echo "  - Memory overhead: +25%"
        ADJUSTED_MB=$((EXPECTED_MB * 125 / 100))
        ;;
    *)
        echo "Configuration: Balanced (default)"
        echo "  - Standard frequency: 2.0 GHz"
        echo "  - Standard power: 100W"
        echo "  - No adjustment"
        ADJUSTED_MB=$EXPECTED_MB
        ;;
esac

echo "  Adjusted for config: ${ADJUSTED_MB}MB ($(echo "scale=1; $ADJUSTED_MB/1024" | bc)GB)"
echo ""

# Test memory allocation
ALLOC_GB=$(echo "scale=0; $ADJUSTED_MB / 1024" | bc)
echo "Testing Memory Allocation:"
echo "  Attempting to allocate ${ALLOC_GB}GB..."

python3 << EOFPY
import sys
try:
    # Allocate the adjusted amount
    alloc_bytes = ${ADJUSTED_MB} * 1024 * 1024
    data = bytearray(alloc_bytes)
    # Touch memory to ensure allocation
    for i in range(0, alloc_bytes, 1024*1024):
        data[i] = i % 256
    print(f"  ✓ SUCCESS: Allocated ${ALLOC_GB}GB")
    print(f"  Memory test passed!")
except MemoryError as e:
    print(f"  ✗ FAILED: OOM - Could not allocate ${ALLOC_GB}GB")
    print(f"  Error: {e}")
    sys.exit(1)
EOFPY

echo ""
echo "Job Complete: $(date '+%Y-%m-%d %H:%M:%S')"
echo "═══════════════════════════════════════════════════════════"
EOFWORK

chmod +x workload.sh

echo "Submitting test jobs..."
echo ""

# Submit all scenarios
JOB_IDS=()
for scenario in "${SCENARIOS[@]}"; do
    IFS=':' read -r name gates initial expected config <<< "$scenario"
    
    echo "Submitting: $name (${gates} gates, ${initial}MB → ${expected}MB, $config)"
    
    JOB_ID=$(sbatch \
        --export=ALL,DESIGN_GATES=$gates,DESIGN_CONFIG=$config \
        --mem=${initial}M \
        --job-name="test_${name}" \
        --output="result_${name}_%j.txt" \
        workload.sh | grep -oP '\d+$')
    
    JOB_IDS+=($JOB_ID)
    echo "  Job ID: $JOB_ID"
    sleep 1
done

echo ""
echo "Waiting for jobs to complete..."
echo "────────────────────────────────────────────────────────────"

# Monitor progress
while squeue -h -u $USER 2>/dev/null | grep -q "test_"; do
    RUNNING=$(squeue -h -u $USER -t R -n "test_" 2>/dev/null | wc -l)
    PENDING=$(squeue -h -u $USER -t PD -n "test_" 2>/dev/null | wc -l)
    echo "[$(date +%H:%M:%S)] Running: $RUNNING, Pending: $PENDING"
    sleep 5
done

echo "[$(date +%H:%M:%S)] All jobs completed"
echo ""

# Analyze results
echo "════════════════════════════════════════════════════════════"
echo "  Test Results"
echo "════════════════════════════════════════════════════════════"
echo ""

SUCCESS=0
FAILED=0

for scenario in "${SCENARIOS[@]}"; do
    IFS=':' read -r name gates initial expected config <<< "$scenario"
    
    RESULT_FILE=$(ls result_${name}_*.txt 2>/dev/null | head -1)
    
    if [ -f "$RESULT_FILE" ]; then
        echo "Test: $name"
        echo "────────────────────────────────────────────────────────────"
        
        if grep -q "✓ SUCCESS" "$RESULT_FILE"; then
            echo "  Status: ✓ PASSED"
            SUCCESS=$((SUCCESS + 1))
        else
            echo "  Status: ✗ FAILED"
            FAILED=$((FAILED + 1))
        fi
        
        # Extract key metrics
        grep "Gates:" "$RESULT_FILE" | sed 's/^/  /'
        grep "Configuration:" "$RESULT_FILE" | head -1 | sed 's/^/  /'
        grep "Total Expected:" "$RESULT_FILE" | sed 's/^/  /'
        grep "Adjusted for config:" "$RESULT_FILE" | sed 's/^/  /'
        grep "SUCCESS\|FAILED" "$RESULT_FILE" | sed 's/^/  /'
        echo ""
    else
        echo "Test: $name - No output file found"
        echo ""
        FAILED=$((FAILED + 1))
    fi
done

echo "════════════════════════════════════════════════════════════"
echo "  Summary"
echo "════════════════════════════════════════════════════════════"
echo ""
echo "Total Tests: ${#SCENARIOS[@]}"
echo "Passed: $SUCCESS"
echo "Failed: $FAILED"
echo "Success Rate: $(echo "scale=1; $SUCCESS * 100 / ${#SCENARIOS[@]}" | bc)%"
echo ""

# Check job_submit plugin logs
echo "Job Submit Plugin Activity:"
echo "────────────────────────────────────────────────────────────"
grep "job_submit.*DESIGN_GATES" /var/log/slurmctld.log 2>/dev/null | tail -10 || echo "No plugin logs found"
echo ""

echo "Detailed results available in: $(pwd)"
echo ""
