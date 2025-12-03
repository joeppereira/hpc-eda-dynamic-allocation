# Resource Management Configuration Possibilities

This document explains all the ways you can configure and adjust resources in SLURM, what can be changed, when, and how.

---

## Question 1: Can We Increase Memory Only?

### Short Answer
**It depends on WHEN and HOW:**

| Scenario | Increase Memory Only? | Mechanism |
|----------|----------------------|-----------|
| **Before job starts** | ✅ Yes | Job submit plugin, user request |
| **At job launch** | ✅ Yes (within SLURM allocation) | SPANK plugin, prolog script |
| **During execution (single-node)** | ❌ No | SLURM doesn't support this |
| **During execution (multi-node)** | ✅ Yes (by adding nodes) | Elastic jobs |

### Detailed Explanation

#### Option 1: Increase Memory Before Job Starts

```bash
# User submits with 4GB
sbatch --mem=4GB job.sh

# Job submit plugin increases to 12GB BEFORE scheduling
# Location: /opt/slurm/etc/job_submit.lua

function slurm_job_submit(job_desc, part_list, submit_uid)
  -- Read design parameters
  local gates = job_desc.environment["DESIGN_GATES"]
  
  if gates then
    -- Calculate required memory
    local required_mb = 2000 + (gates * 0.08)
    local safe_mb = required_mb * 1.2
    
    -- MODIFY memory request
    job_desc.min_mem_per_node = safe_mb  -- ← Changes from 4GB to 12GB
  end
  
  return slurm.SUCCESS
end
```

**Result:** Job is scheduled with 12GB instead of 4GB  
**When:** Before SLURM schedules the job  
**Can change:** ✅ Memory, ✅ CPUs, ✅ Nodes, ✅ Time limit  

#### Option 2: Adjust Memory at Launch (Within Allocation)

```c
// SPANK plugin: spank/spank_dynamic_alloc.c
// Runs AFTER SLURM allocates, BEFORE process starts

int slurm_spank_task_post_fork(spank_t sp, int ac, char **av) {
  // SLURM already allocated 12GB
  // We set process limit to 10GB (within the 12GB)
  
  struct rlimit rlim;
  rlim.rlim_cur = 10 * 1024 * 1024 * 1024;  // 10GB
  rlim.rlim_max = 10 * 1024 * 1024 * 1024;
  
  setrlimit(RLIMIT_AS, &rlim);  // ← Process limited to 10GB
  
  return SLURM_SUCCESS;
}
```

**Result:** Process uses 10GB within 12GB SLURM allocation  
**When:** After allocation, before execution  
**Can change:** ✅ Process limits (within SLURM allocation)  
**Cannot change:** ❌ SLURM allocation itself  

#### Option 3: Increase Memory During Execution (Elastic Jobs)

```bash
# Submit elastic job with node range
sbatch --nodes=2-10 --mem=0 elastic_job.sh
#              ↑   ↑        ↑
#              min max      use all node memory

# Job starts with 2 nodes
# Initial memory: 2 × 64GB = 128GB

# SLURM adds 3 more nodes during execution
# New memory: 5 × 64GB = 320GB  ← Memory increased!
```

**Result:** Total memory increases by adding nodes  
**When:** During job execution  
**Can change:** ✅ Number of nodes (which increases total memory)  
**Cannot change:** ❌ Memory per node  

---

## All Resource Management Configuration Possibilities

### 1. Job Submission Time (User Control)

```bash
# User specifies resources when submitting
sbatch \
  --nodes=2 \              # Number of nodes
  --ntasks=8 \             # Number of tasks/processes
  --cpus-per-task=4 \      # CPUs per task
  --mem=16G \              # Memory per node
  --mem-per-cpu=2G \       # Alternative: memory per CPU
  --time=02:00:00 \        # Time limit
  --gres=gpu:2 \           # Generic resources (GPUs)
  --constraint=haswell \   # Node features
  job.sh
```

**What can be specified:**
- ✅ Nodes (fixed count or range for elastic)
- ✅ CPUs
- ✅ Memory (per node or per CPU)
- ✅ Time limit
- ✅ GPUs and other resources
- ✅ Node constraints

### 2. Job Submit Plugin (Automatic Modification)

```lua
-- Location: /opt/slurm/etc/job_submit.lua
-- Runs: Before job is scheduled
-- Can modify: Almost everything

function slurm_job_submit(job_desc, part_list, submit_uid)
  -- Can modify:
  job_desc.min_mem_per_node = 12288      -- ✅ Memory
  job_desc.min_cpus = 4                   -- ✅ CPUs
  job_desc.time_limit = 120               -- ✅ Time limit
  job_desc.partition = "compute"          -- ✅ Partition
  job_desc.qos = "high"                   -- ✅ QOS
  
  -- Cannot modify:
  -- ❌ Resources after job starts
  
  return slurm.SUCCESS
end
```

**Capabilities:**
- ✅ Modify any job parameter before scheduling
- ✅ Based on user input, design parameters, policies
- ❌ Cannot change after job starts

### 3. Prolog Script (Node Setup)

```bash
#!/bin/bash
# Location: /opt/slurm/etc/prolog.sh
# Runs: On compute node before job starts
# Can: Configure node environment

# Can do:
# ✅ Set environment variables
export CUSTOM_VAR="value"

# ✅ Create directories
mkdir -p /tmp/job_$SLURM_JOB_ID

# ✅ Mount filesystems
mount -t nfs server:/data /mnt/data

# ✅ Configure cgroups (if root)
echo $((12 * 1024 * 1024 * 1024)) > \
  /sys/fs/cgroup/memory/slurm/uid_$SLURM_JOB_UID/job_$SLURM_JOB_ID/memory.limit_in_bytes

# Cannot do:
# ❌ Change SLURM allocation
# ❌ Request more resources from SLURM
```

**Capabilities:**
- ✅ Node-level setup
- ✅ Environment configuration
- ✅ Cgroup manipulation (if root)
- ❌ Cannot change SLURM allocation

### 4. SPANK Plugin (Process-Level Control)

```c
// Location: /opt/slurm/lib/slurm/spank_plugin.so
// Runs: Multiple hooks during job lifecycle
// Can: Set process limits, monitor, log

int slurm_spank_task_post_fork(spank_t sp, int ac, char **av) {
  // Can set process limits (within SLURM allocation)
  
  struct rlimit rlim;
  
  // ✅ Memory limit
  rlim.rlim_cur = 10 * 1024 * 1024 * 1024;
  setrlimit(RLIMIT_AS, &rlim);
  
  // ✅ CPU time limit
  rlim.rlim_cur = 3600;  // 1 hour
  setrlimit(RLIMIT_CPU, &rlim);
  
  // ✅ File size limit
  rlim.rlim_cur = 10 * 1024 * 1024 * 1024;  // 10GB
  setrlimit(RLIMIT_FSIZE, &rlim);
  
  // ✅ Number of open files
  rlim.rlim_cur = 4096;
  setrlimit(RLIMIT_NOFILE, &rlim);
  
  // ❌ Cannot request more from SLURM
  
  return SLURM_SUCCESS;
}
```

**Capabilities:**
- ✅ Set process resource limits (rlimits)
- ✅ Monitor resource usage
- ✅ Log events
- ❌ Cannot exceed SLURM allocation

### 5. Runtime Modification (scontrol)

```bash
# Modify running job (very limited)
scontrol update jobid=12345 TimeLimit=+60  # ✅ Extend time

# What CAN be changed:
scontrol update jobid=12345 \
  TimeLimit=04:00:00 \     # ✅ Time limit
  Priority=1000 \          # ✅ Priority
  QOS=high \               # ✅ QOS
  Comment="Updated"        # ✅ Comment

# What CANNOT be changed:
scontrol update jobid=12345 \
  NumNodes=5 \             # ❌ Node count (for running job)
  MinMemoryNode=16G \      # ❌ Memory
  NumCPUs=8                # ❌ CPUs
# Error: Cannot modify these for running jobs
```

**Capabilities:**
- ✅ Time limit
- ✅ Priority, QOS
- ✅ Job name, comment
- ❌ Memory, CPUs, nodes (for running jobs)

### 6. Elastic Jobs (Runtime Scaling)

```bash
# Submit with node range
sbatch --nodes=2-10 elastic_job.sh

# What CAN change during execution:
# ✅ Number of nodes (2 → 5 → 8 → 3)
# ✅ Total memory (128GB → 320GB → 512GB → 192GB)
# ✅ Total CPUs (32 → 80 → 128 → 48)

# What CANNOT change:
# ❌ Memory per node (always 64GB per node)
# ❌ CPUs per node (always 16 CPUs per node)
# ❌ Node type/configuration
```

**Capabilities:**
- ✅ Add/remove nodes during execution
- ✅ Total memory scales with node count
- ✅ Total CPUs scale with node count
- ❌ Per-node resources are fixed

---

## Elastic Jobs with PMIx/MPI Explained

### What is PMIx?

**PMIx (Process Management Interface - Exascale)** is a standard API that allows:
- MPI applications to communicate with resource managers (SLURM)
- Dynamic process management (spawn/kill processes)
- Notification of resource changes
- Coordination between application and scheduler

### How Elastic Jobs Work

```
┌─────────────────────────────────────────────────────────────┐
│ Step 1: Job Submission                                      │
│                                                             │
│ $ sbatch --nodes=2-10 elastic_job.sh                       │
│                                                             │
│ SLURM understands:                                          │
│ - Minimum: 2 nodes required                                 │
│ - Maximum: 10 nodes allowed                                 │
│ - Can grow/shrink between these limits                      │
└─────────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────────┐
│ Step 2: Initial Allocation                                  │
│                                                             │
│ SLURM allocates minimum (2 nodes):                          │
│ - Node 1: 64GB RAM, 16 CPUs                                 │
│ - Node 2: 64GB RAM, 16 CPUs                                 │
│ Total: 128GB RAM, 32 CPUs                                   │
└─────────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────────┐
│ Step 3: MPI Application Starts                              │
│                                                             │
│ mpirun -n 8 my_app                                          │
│                                                             │
│ PMIx initializes:                                           │
│ - Registers with SLURM                                      │
│ - Sets up communication channels                            │
│ - Enables dynamic process management                        │
│                                                             │
│ Application code:                                           │
│ from mpi4py import MPI                                      │
│ comm = MPI.COMM_WORLD                                       │
│ size = comm.Get_size()  # Returns 8 initially              │
└─────────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────────┐
│ Step 4: SLURM Detects Available Resources                   │
│                                                             │
│ SLURM scheduler monitors:                                   │
│ - 3 more nodes became idle                                  │
│ - Job's partition allows elastic scaling                    │
│ - Job is still running                                      │
│ - Job requested up to 10 nodes                              │
│                                                             │
│ Decision: Grow job from 2 to 5 nodes                        │
└─────────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────────┐
│ Step 5: SLURM Allocates Additional Nodes                    │
│                                                             │
│ SLURM adds:                                                 │
│ - Node 3: 64GB RAM, 16 CPUs                                 │
│ - Node 4: 64GB RAM, 16 CPUs                                 │
│ - Node 5: 64GB RAM, 16 CPUs                                 │
│                                                             │
│ New total: 320GB RAM, 80 CPUs                               │
└─────────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────────┐
│ Step 6: PMIx Notifies Application                           │
│                                                             │
│ PMIx sends event to application:                            │
│ - Event type: PMIX_ERR_PROC_REQUESTED                       │
│ - New resources available                                   │
│ - Node list: node3, node4, node5                            │
│                                                             │
│ Application's event handler is called                       │
└─────────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────────┐
│ Step 7: MPI Spawns New Processes                            │
│                                                             │
│ MPI runtime (OpenMPI/MPICH):                                │
│ - Spawns 12 new processes on new nodes                      │
│ - Integrates them into MPI_COMM_WORLD                       │
│ - Updates process count                                     │
│                                                             │
│ Application now has:                                        │
│ - 20 processes (was 8, added 12)                            │
│ - comm.Get_size() returns 20                                │
└─────────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────────┐
│ Step 8: Application Redistributes Work                      │
│                                                             │
│ Application code:                                           │
│ while work_remaining:                                       │
│     # Re-check size (may have changed!)                     │
│     size = comm.Get_size()  # Now returns 20                │
│     rank = comm.Get_rank()                                  │
│                                                             │
│     # Redistribute work across all processes                │
│     my_chunk = total_work / size                            │
│     my_work = get_chunk(rank, my_chunk)                     │
│                                                             │
│     # Process my portion                                    │
│     result = process(my_work)                               │
│                                                             │
│     # Gather results                                        │
│     all_results = comm.gather(result, root=0)               │
└─────────────────────────────────────────────────────────────┘
```

### Memory Increase Mechanism

```
Initial State (2 nodes):
┌──────────┐  ┌──────────┐
│  Node 1  │  │  Node 2  │
│  64GB    │  │  64GB    │
│  8 procs │  │  8 procs │
└──────────┘  └──────────┘
Total: 128GB, 16 processes

After Growth (5 nodes):
┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐
│  Node 1  │  │  Node 2  │  │  Node 3  │  │  Node 4  │  │  Node 5  │
│  64GB    │  │  64GB    │  │  64GB    │  │  64GB    │  │  64GB    │
│  4 procs │  │  4 procs │  │  4 procs │  │  4 procs │  │  4 procs │
└──────────┘  └──────────┘  └──────────┘  └──────────┘  └──────────┘
Total: 320GB, 20 processes

Memory increased by: 320GB - 128GB = 192GB (150% increase)
```

### Key Points

1. **Memory increases by adding nodes**, not by increasing per-node memory
2. **Application must be MPI-aware** and handle dynamic process changes
3. **PMIx is the communication layer** between SLURM and MPI
4. **SLURM decides when to grow/shrink** based on cluster availability
5. **Application redistributes work** when resources change

### Requirements for Elastic Jobs

```bash
# 1. SLURM configuration
# /opt/slurm/etc/slurm.conf
PartitionName=compute ElasticPartition=yes

# 2. PMIx-enabled MPI
module load openmpi/4.1.6  # Must be compiled with --with-pmix

# 3. Application support
# Application must:
# - Use MPI
# - Handle dynamic process count changes
# - Redistribute work when size changes
```

---

## Summary: What Can Be Changed and When

| Resource | Before Start | At Launch | During Execution (Single-Node) | During Execution (Multi-Node) |
|----------|--------------|-----------|-------------------------------|------------------------------|
| **Memory** | ✅ Yes (job_submit) | ✅ Yes (SPANK, within allocation) | ❌ No | ✅ Yes (add nodes) |
| **CPUs** | ✅ Yes (job_submit) | ✅ Yes (SPANK, affinity) | ❌ No | ✅ Yes (add nodes) |
| **Nodes** | ✅ Yes (job_submit) | ❌ No | ❌ No | ✅ Yes (elastic) |
| **Time Limit** | ✅ Yes (job_submit) | ❌ No | ✅ Yes (scontrol) | ✅ Yes (scontrol) |
| **Priority** | ✅ Yes (job_submit) | ❌ No | ✅ Yes (scontrol) | ✅ Yes (scontrol) |

**Bottom line:** For single-node jobs, memory can only be set before or at launch. For multi-node elastic jobs, total memory can increase by adding nodes during execution.

