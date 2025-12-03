#!/bin/bash
# SLURM Prolog Script - Dynamic Memory Allocation
# Runs on compute node before job starts
# Can modify cgroup memory limits

# Get job info from SLURM environment
JOB_ID=${SLURM_JOB_ID}
JOB_MEM=${SLURM_MEM_PER_NODE}  # In MB
JOB_USER=${SLURM_JOB_USER}

# Log to syslog
logger -t "prolog_dynamic" "Job $JOB_ID starting for user $JOB_USER with ${JOB_MEM}MB"

# Check for DESIGN_GATES environment variable
GATES=${DESIGN_GATES:-0}

if [ "$GATES" -gt 0 ]; then
    logger -t "prolog_dynamic" "Job $JOB_ID: Detected DESIGN_GATES=$GATES"
    
    # Calculate required memory (same formula as SPANK)
    BASE_MB=2000
    CALCULATED_MB=$((BASE_MB + GATES * 8 / 100))
    BUFFER_MB=$((CALCULATED_MB * 20 / 100))
    REQUIRED_MB=$((CALCULATED_MB + BUFFER_MB))
    
    logger -t "prolog_dynamic" "Job $JOB_ID: Calculated ${REQUIRED_MB}MB needed (${CALCULATED_MB}MB + ${BUFFER_MB}MB buffer)"
    
    # Check if adjustment needed
    if [ "$REQUIRED_MB" -gt "$JOB_MEM" ]; then
        SHORTFALL=$((REQUIRED_MB - JOB_MEM))
        logger -t "prolog_dynamic" "Job $JOB_ID: Insufficient! Need ${REQUIRED_MB}MB, have ${JOB_MEM}MB (shortfall: ${SHORTFALL}MB)"
        
        # Find job's cgroup
        CGROUP_PATH="/sys/fs/cgroup/memory/slurm/uid_${SLURM_JOB_UID}/job_${JOB_ID}"
        
        if [ -d "$CGROUP_PATH" ]; then
            # Adjust cgroup memory limit
            REQUIRED_BYTES=$((REQUIRED_MB * 1024 * 1024))
            echo $REQUIRED_BYTES > ${CGROUP_PATH}/memory.limit_in_bytes 2>/dev/null
            
            if [ $? -eq 0 ]; then
                logger -t "prolog_dynamic" "Job $JOB_ID: ✓ Adjusted cgroup memory to ${REQUIRED_MB}MB"
            else
                logger -t "prolog_dynamic" "Job $JOB_ID: ✗ Failed to adjust cgroup memory"
            fi
        else
            logger -t "prolog_dynamic" "Job $JOB_ID: Cgroup not found at $CGROUP_PATH"
        fi
    else
        logger -t "prolog_dynamic" "Job $JOB_ID: ✓ Current allocation (${JOB_MEM}MB) is sufficient"
    fi
else
    logger -t "prolog_dynamic" "Job $JOB_ID: No DESIGN_GATES specified, skipping adjustment"
fi

exit 0
