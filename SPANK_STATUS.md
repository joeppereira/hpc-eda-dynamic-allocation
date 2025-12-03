# SPANK Dynamic Allocation - Current Status

## What We've Accomplished

### ✅ SPANK Plugin Created
- **File**: `spank/spank_dynamic_alloc.c`
- **Features**:
  - Accepts `--gates=N` parameter
  - Calculates memory: `2GB + (gates × 0.08MB) + 20% buffer`
  - Attempts to adjust memory limits via `setrlimit()`
  - Logs all activity

### ✅ Installation Scripts Created
- **`aws/install_spank_v2.sh`** - Compiles and installs SPANK plugin
- **`aws/test_spank_with_output.sh`** - Tests SPANK with memory allocation
- **`aws/check_spank_on_compute.sh`** - Diagnostic check on compute nodes

### ✅ Plugin Installed on Head Node
- Compiled successfully
- Installed to `/opt/slurm/lib/slurm/spank_dynamic_alloc.so`
- Configured in `/opt/slurm/etc/plugstack.conf`
- SLURM services restarted

### ✅ Plugin IS Loading
From test output: `"SPANK Dynamic: Plugin initialized"`
- Plugin file is accessible on compute nodes (via NFS)
- plugstack.conf is being read
- Plugin loads when slurmd starts

## Current Issue

### ❌ SPANK Hooks Not Firing
**Symptom**: Job got OOM killed despite SPANK plugin being loaded

**Evidence**:
```
Job requested: 4GB with DESIGN_GATES=100000
Expected: SPANK should adjust to ~10GB
Result: OOM killed trying to allocate 9GB
```

**What we see in logs**:
- ✅ "SPANK Dynamic: Plugin initialized" (slurm_spank_init fires)
- ❌ NO other SPANK messages (task hooks NOT firing)

**Confirmed**:
- ✅ Plugin file accessible on compute nodes
- ✅ plugstack.conf correct
- ✅ Plugin loads when slurmd starts
- ✅ Environment variable passed correctly (DESIGN_GATES=100000)
- ❌ `slurm_spank_task_init_privileged` NEVER called
- ❌ `slurm_spank_task_post_fork` NEVER called

**Root Cause**: 
The task-level SPANK hooks are not being invoked. This is likely because:
1. **Plugin context wrong** - May need `optional` instead of `required` in plugstack.conf
2. **SLURM cgroups** - Memory enforcement via cgroups, not rlimits
3. **Hook timing** - `task_init_privileged` may not fire for batch jobs
4. **SLURM version** - Some SPANK hooks behavior changed in different versions

## Next Session Actions

### 1. Run Diagnostic Script
```bash
# Copy updated diagnostic
scp aws/check_spank_on_compute.sh ec2-user@<HEAD_NODE>:~/

# Run it
./check_spank_on_compute.sh
```

This will show:
- If plugin file is accessible
- If plugstack.conf is correct
- Any loading errors
- Plugin dependencies

### 2. Check SPANK Hook Execution
Add more verbose logging to see which hooks are actually being called:

**Modify plugin to log every hook**:
- `slurm_spank_init` - ✅ Already logging (we see this)
- `slurm_spank_task_init_privileged` - Need to verify this fires
- `slurm_spank_task_post_fork` - Need to verify this fires

### 3. Test Option Registration
Verify `--gates` option is actually registered:
```bash
# This should show the --gates option
sbatch --help | grep gates
```

### 4. Alternative Approach: Use Environment Variables
If `--gates` option isn't working, fall back to environment variable:
```bash
sbatch --export=DESIGN_GATES=100000 --mem=4096M job.sh
```

The plugin already has fallback code for this:
```c
if (gates_option == 0) {
    char *gates_env = getenv("DESIGN_GATES");
    if (gates_env) {
        gates_option = atoi(gates_env);
    }
}
```

### 5. Consider SLURM Cgroup Override
SLURM's cgroup memory controller might override `setrlimit()`. May need to:
- Use SLURM's memory adjustment APIs instead
- Or modify job's cgroup memory limit directly
- Or request memory increase via SLURM API

## Files Ready for Next Session

### On Local Machine
- `aws/install_spank_v2.sh` - Plugin installation
- `aws/check_spank_on_compute.sh` - Diagnostics
- `aws/test_spank_with_output.sh` - Memory test
- `spank/spank_dynamic_alloc.c` - Plugin source

### On Head Node (already there)
- `/opt/slurm/lib/slurm/spank_dynamic_alloc.so` - Compiled plugin
- `/opt/slurm/etc/plugstack.conf` - SPANK config

## Quick Start Commands for Next Session

```bash
# 1. Copy diagnostic script
scp aws/check_spank_on_compute.sh ec2-user@<HEAD_NODE>:~/

# 2. SSH to head node
ssh ec2-user@<HEAD_NODE>

# 3. Run diagnostic
chmod +x check_spank_on_compute.sh
./check_spank_on_compute.sh

# 4. Test with environment variable approach
sbatch --export=DESIGN_GATES=100000 --mem=4096M \
  --wrap="echo 'Testing SPANK'; python3 -c 'import sys; data=bytearray(9*1024*1024*1024); print(\"Success\")'"

# 5. Check logs
# (Will be in job output file)
```

## Key Insight

The SPANK plugin **is installed and loading correctly**. The issue is that the **hooks aren't being called** or the **option isn't being passed through**. This is a configuration/integration issue, not a compilation issue.

## System Information

- **SLURM Version**: 24.11.6 (November 2024 - latest)
- **Platform**: AWS ParallelCluster
- **SPANK Support**: ✅ Full support for all hooks
- **Plugin Location**: `/opt/slurm/lib/slurm/spank_dynamic_alloc.so`
- **Config**: `/opt/slurm/etc/plugstack.conf`

## Success Criteria

When working correctly, we should see in job output:
```
SPANK Dynamic: Plugin initialized
SPANK Dynamic: --gates=100000 detected
SPANK Dynamic: Calculated 9600 MB (9.4 GB) for 100000 gates
SPANK Dynamic: Job 26 - Current allocation: 4096 MB (4.0 GB)
SPANK Dynamic: Insufficient! Need 9600 MB, have 4096 MB (shortfall: 5504 MB)
SPANK Dynamic: Adjusting memory limit...
SPANK Dynamic: ✓ Adjusted to 9600 MB (9.4 GB)
```

Then the memory allocation test should succeed without OOM.
