# Checkpoint and Restart for OpenROAD Jobs

## Current State: OpenROAD Flow

### Native OpenROAD Checkpointing

**OpenROAD itself does NOT have built-in checkpointing**

Each stage writes output files:
```
synthesis    → netlist.v
floorplan    → floorplan.def
placement    → placement.def
cts          → cts.def
routing      → routing.def
finishing    → final.gds
```

### Restart Capability: ✅ YES (Stage-Level)

**OpenROAD-flow-scripts supports stage-level restart:**

```bash
# Run full flow
make DESIGN_CONFIG=designs/asap7/gcd/config.mk

# If it fails at routing, you can restart from there:
make DESIGN_CONFIG=designs/asap7/gcd/config.mk route

# Or restart from specific stage:
make DESIGN_CONFIG=designs/asap7/gcd/config.mk floorplan
make DESIGN_CONFIG=designs/asap7/gcd/config.mk place
make DESIGN_CONFIG=designs/asap7/gcd/config.mk cts
make DESIGN_CONFIG=designs/asap7/gcd/config.mk route
```

**How it works:**
- Each stage reads input from previous stage's output file
- If output file exists, stage can be skipped or rerun
- Makefile tracks dependencies

## SLURM Checkpoint/Restart

### Option 1: SLURM Job Checkpointing (Limited)

**SLURM's built-in checkpointing:**
```bash
sbatch --checkpoint=30  # Checkpoint every 30 minutes
```

**Limitations:**
- ❌ Requires application support (OpenROAD doesn't have it)
- ❌ Needs BLCR (Berkeley Lab Checkpoint/Restart) - deprecated
- ❌ Not widely supported anymore

**Verdict**: Not practical for OpenROAD

### Option 2: Stage-Based Restart (RECOMMENDED)

**Implement stage-level checkpointing in SLURM job:**

```bash
#!/bin/bash
#SBATCH --job-name=openroad_gcd
#SBATCH --time=04:00:00
#SBATCH --checkpoint=30
#SBATCH --checkpoint-dir=/scratch/checkpoints

# Track completed stages
CHECKPOINT_FILE="/scratch/checkpoints/${SLURM_JOB_ID}_stages.txt"

# Function to run stage with checkpoint
run_stage() {
    STAGE=$1
    
    # Check if stage already completed
    if grep -q "^${STAGE}$" "$CHECKPOINT_FILE" 2>/dev/null; then
        echo "Stage ${STAGE} already completed, skipping..."
        return 0
    fi
    
    # Run stage
    echo "Running stage: ${STAGE}"
    make DESIGN_CONFIG=config.mk ${STAGE}
    
    # Mark as completed
    if [ $? -eq 0 ]; then
        echo "${STAGE}" >> "$CHECKPOINT_FILE"
        echo "Stage ${STAGE} completed successfully"
    else
        echo "Stage ${STAGE} failed"
        exit 1
    fi
}

# Run stages with checkpointing
run_stage "synth"
run_stage "floorplan"
run_stage "place"
run_stage "cts"
run_stage "route"
run_stage "finish"

echo "All stages completed!"
```

**Benefits:**
- ✅ Can restart from any completed stage
- ✅ No application modification needed
- ✅ Works with SLURM preemption
- ✅ Saves compute time on restarts

### Option 3: DMTCP (Distributed MultiThreaded CheckPointing)

**User-space checkpointing:**

```bash
# Install DMTCP
module load dmtcp

# Run with DMTCP
dmtcp_launch openroad script.tcl

# Checkpoint manually
dmtcp_command --checkpoint

# Restart from checkpoint
dmtcp_restart ckpt_*.dmtcp
```

**Pros:**
- ✅ Application-transparent
- ✅ Can checkpoint any process
- ✅ Works with MPI

**Cons:**
- ❌ Overhead (5-10%)
- ❌ Large checkpoint files
- ❌ May not work with all applications
- ❌ Complex setup

### Option 4: Container Checkpointing (CRIU)

**Checkpoint entire container:**

```bash
# Checkpoint Docker container
docker checkpoint create <container_id> checkpoint1

# Restore from checkpoint
docker start --checkpoint checkpoint1 <container_id>
```

**Pros:**
- ✅ Checkpoints entire container state
- ✅ Can migrate between nodes

**Cons:**
- ❌ Experimental feature
- ❌ Not all Docker versions support it
- ❌ Large checkpoint files
- ❌ Doesn't work with all workloads

## Recommendation for Our Project

### For Local Testing (Docker):
**Use Stage-Level Restart**
```bash
# Run stages individually
docker run openroad/orfs make synth
docker run openroad/orfs make place
docker run openroad/orfs make route

# If one fails, restart from that stage
```

### For Production (SLURM):
**Implement Stage-Based Checkpointing**

```bash
#!/bin/bash
#SBATCH --job-name=openroad_checkpoint
#SBATCH --time=04:00:00
#SBATCH --signal=B:SIGUSR1@300  # Signal 5 min before timeout

# Checkpoint on signal
trap 'echo "Job interrupted, checkpoint saved"; exit 130' SIGUSR1

# Stage tracking
STAGE_FILE="${SLURM_JOB_ID}_progress.txt"

# Resume from last completed stage
if [ -f "$STAGE_FILE" ]; then
    LAST_STAGE=$(tail -1 "$STAGE_FILE")
    echo "Resuming from stage: $LAST_STAGE"
fi

# Run stages with progress tracking
for stage in synth floorplan place cts route finish; do
    if ! grep -q "^${stage}$" "$STAGE_FILE" 2>/dev/null; then
        echo "Running: $stage"
        make $stage && echo "$stage" >> "$STAGE_FILE"
    fi
done
```

### For SPANK Plugin Integration:

**Track stage completion in SPANK plugin:**

```c
// In SPANK plugin
int slurm_spank_job_epilog(spank_t sp, int ac, char **av) {
    // Save stage completion status
    save_checkpoint_state(job_id, completed_stages);
    
    // On restart, resume from last completed stage
    if (is_restart) {
        load_checkpoint_state(job_id, &completed_stages);
        skip_completed_stages(completed_stages);
    }
}
```

## Summary

| Method | Granularity | Overhead | Complexity | Recommended |
|--------|-------------|----------|------------|-------------|
| **Stage-Level** | Per stage | 0% | Low | ✅ **YES** |
| SLURM Native | Full job | N/A | High | ❌ No (deprecated) |
| DMTCP | Any point | 5-10% | Medium | ⚠️ Maybe |
| CRIU | Container | 10-20% | High | ❌ No (experimental) |

**Best Approach**: 
- Implement **stage-level checkpointing** in job scripts
- Track completed stages in file
- Resume from last completed stage on restart
- Integrate with SPANK plugin for automatic tracking

**Benefits**:
- ✅ Zero overhead during execution
- ✅ Fast restart (skip completed stages)
- ✅ Works with SLURM preemption
- ✅ Simple to implement
- ✅ No special tools required
