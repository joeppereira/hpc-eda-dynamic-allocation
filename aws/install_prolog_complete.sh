#!/bin/bash
# Complete prolog installation - includes script inline

set -e

echo "════════════════════════════════════════════════════════════"
echo "  SLURM Prolog Script - Dynamic Memory Allocation"
echo "════════════════════════════════════════════════════════════"
echo ""

# Create prolog directory
echo "Step 1: Creating prolog directory..."
sudo mkdir -p /opt/slurm/etc/scripts/prolog.d
sudo chmod 755 /opt/slurm/etc/scripts/prolog.d
echo "✓ Directory created"
echo ""

# Create prolog script inline
echo "Step 2: Creating prolog script..."
sudo tee /opt/slurm/etc/scripts/prolog.d/prolog_dynamic_alloc.sh > /dev/null << 'EOFPROLOG'
#!/bin/bash
# SLURM Prolog - Dynamic Memory Allocation
# Runs before job starts on compute node

JOB_ID=${SLURM_JOB_ID}
JOB_MEM=${SLURM_MEM_PER_NODE}
JOB_USER=${SLURM_JOB_USER}

logger -t "prolog_dynamic" "Job $JOB_ID starting for $JOB_USER with ${JOB_MEM}MB"

GATES=${DESIGN_GATES:-0}

if [ "$GATES" -gt 0 ]; then
    logger -t "prolog_dynamic" "Job $JOB_ID: DESIGN_GATES=$GATES"
    
    # Calculate memory (base + gates*0.08 + 20% buffer)
    BASE_MB=2000
    CALCULATED_MB=$((BASE_MB + GATES * 8 / 100))
    BUFFER_MB=$((CALCULATED_MB * 20 / 100))
    REQUIRED_MB=$((CALCULATED_MB + BUFFER_MB))
    
    logger -t "prolog_dynamic" "Job $JOB_ID: Need ${REQUIRED_MB}MB (calc: ${CALCULATED_MB}MB + buffer: ${BUFFER_MB}MB)"
    
    if [ "$REQUIRED_MB" -gt "$JOB_MEM" ]; then
        SHORTFALL=$((REQUIRED_MB - JOB_MEM))
        logger -t "prolog_dynamic" "Job $JOB_ID: Insufficient! ${JOB_MEM}MB allocated, ${REQUIRED_MB}MB needed (shortfall: ${SHORTFALL}MB)"
        
        # Try to adjust cgroup memory
        CGROUP_BASE="/sys/fs/cgroup/memory/slurm"
        
        # Try different cgroup paths
        for CGROUP_PATH in \
            "${CGROUP_BASE}/uid_${SLURM_JOB_UID}/job_${JOB_ID}" \
            "${CGROUP_BASE}/job_${JOB_ID}" \
            "/sys/fs/cgroup/slurm/uid_${SLURM_JOB_UID}/job_${JOB_ID}"; do
            
            if [ -d "$CGROUP_PATH" ]; then
                REQUIRED_BYTES=$((REQUIRED_MB * 1024 * 1024))
                
                if echo $REQUIRED_BYTES > ${CGROUP_PATH}/memory.limit_in_bytes 2>/dev/null; then
                    logger -t "prolog_dynamic" "Job $JOB_ID: ✓ Adjusted cgroup to ${REQUIRED_MB}MB at $CGROUP_PATH"
                    exit 0
                fi
            fi
        done
        
        logger -t "prolog_dynamic" "Job $JOB_ID: ⚠ Could not find/adjust cgroup"
    else
        logger -t "prolog_dynamic" "Job $JOB_ID: ✓ ${JOB_MEM}MB is sufficient"
    fi
else
    logger -t "prolog_dynamic" "Job $JOB_ID: No DESIGN_GATES, skipping"
fi

exit 0
EOFPROLOG

sudo chmod 755 /opt/slurm/etc/scripts/prolog.d/prolog_dynamic_alloc.sh
echo "✓ Prolog script created"
echo ""

echo "Step 3: Verifying configuration..."
if grep -q "^Prolog=/opt/slurm/etc/scripts/prolog.d" /opt/slurm/etc/slurm.conf; then
    echo "✓ Prolog already configured in slurm.conf"
else
    echo "⚠  Prolog directory is configured but script may not run"
    echo "   Current Prolog setting:"
    grep "Prolog=" /opt/slurm/etc/slurm.conf || echo "   (not found)"
fi

echo ""
echo "════════════════════════════════════════════════════════════"
echo "  Installation Complete!"
echo "════════════════════════════════════════════════════════════"
echo ""
echo "Prolog script installed at:"
echo "  /opt/slurm/etc/scripts/prolog.d/prolog_dynamic_alloc.sh"
echo ""
echo "Test it:"
echo "  sbatch --export=ALL,DESIGN_GATES=100000 --mem=4096M \\"
echo "    --wrap='echo test; sleep 5'"
echo ""
echo "Check logs (in job output):"
echo "  sbatch --export=ALL,DESIGN_GATES=100000 --mem=4096M \\"
echo "    --wrap='journalctl -t prolog_dynamic --no-pager | tail -20'"
echo ""
