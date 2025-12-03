# Complete System Flow: Data Collection, Tracking, and Resource Allocation

This document shows the complete end-to-end flow of how logs are collected, resources are tracked, and allocations are adjusted in the HPC Resource Optimization system.

---

## Flow 1: Log Collection and Prediction Pipeline

### Stage 1: Job Execution with Monitoring

```
┌─────────────────────────────────────────────────────────────────┐
│ User Submits Job                                                │
│ sbatch --gates=100000 --nets=90000 job.sh                      │
└─────────────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────────────┐
│ SLURM Scheduler (slurmctld)                                     │
│ - Receives job submission                                       │
│ - Allocates compute node                                        │
└─────────────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────────────┐
│ Job Starts on Compute Node                                      │
│ - Singularity container launches: openroad.sif                 │
│ - OpenROAD process begins execution                            │
└─────────────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────────────┐
│ MONITORING LAYER (Parallel to job execution)                   │
│                                                                 │
│ Tool: monitoring/resource_monitor.py                           │
│ - Runs via Python psutil library                               │
│ - Polls every 5 seconds                                         │
│ - Collects:                                                     │
│   • CPU usage (%)                                               │
│   • Memory usage (MB)                                           │
│   • Disk I/O                                                    │
│   • Network I/O                                                 │
│   • Process tree                                                │
└─────────────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────────────┐
│ LOG COLLECTION                                                  │
│                                                                 │
│ Tool: monitoring/openroad_log_parser.py                        │
│ - Parses OpenROAD stdout/stderr                                │
│ - Extracts design parameters:                                  │
│   • Number of gates                                             │
│   • Number of nets                                              │
│   • Number of cells                                             │
│   • Clock frequency                                             │
│   • Utilization                                                 │
│ - Extracts stage information:                                  │
│   • Synthesis time                                              │
│   • Placement time                                              │
│   • Routing time                                                │
│   • Timing analysis time                                        │
└─────────────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────────────┐
│ DATA STORAGE                                                    │
│                                                                 │
│ Location: data/metrics/job_<id>.json                           │
│                                                                 │
│ Format:                                                         │
│ {                                                               │
│   "job_id": "12345",                                            │
│   "design_name": "aes_cipher",                                  │
│   "num_gates": 100000,                                          │
│   "num_nets": 90000,                                            │
│   "cpu_percent": 150.5,                                         │
│   "memory_mb": 12288,                                           │
│   "runtime_seconds": 450,                                       │
│   "timestamp": "2024-12-03T10:30:00",                           │
│   "stages": {                                                   │
│     "synthesis": {"time": 120, "memory": 4096},                 │
│     "placement": {"time": 180, "memory": 8192},                 │
│     "routing": {"time": 150, "memory": 12288}                   │
│   }                                                             │
│ }                                                               │
└─────────────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────────────┐
│ DATABASE IMPORT                                                 │
│                                                                 │
│ Tool: database/import_metrics.py                               │
│ Database: hpc_metrics.db (SQLite)                              │
│                                                                 │
│ Schema (database/schema.py):                                    │
│ CREATE TABLE job_metrics (                                      │
│   id INTEGER PRIMARY KEY,                                       │
│   job_id TEXT,                                                  │
│   design_name TEXT,                                             │
│   num_gates INTEGER,                                            │
│   num_nets INTEGER,                                             │
│   cpu_percent REAL,                                             │
│   memory_mb REAL,                                               │
│   runtime_seconds REAL,                                         │
│   timestamp TEXT                                                │
│ );                                                              │
└─────────────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────────────┐
│ ML MODEL TRAINING                                               │
│                                                                 │
│ Tool: prediction/train_model.py                                │
│ Algorithm: Ridge Regression (scikit-learn)                     │
│                                                                 │
│ Features (X):                                                   │
│ - num_gates                                                     │
│ - num_nets                                                      │
│ - num_cells (optional)                                          │
│                                                                 │
│ Targets (y):                                                    │
│ - cpu_percent                                                   │
│ - memory_mb                                                     │
│ - runtime_seconds                                               │
│                                                                 │
│ Output: prediction/ridge_model.pkl                             │
└─────────────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────────────┐
│ PREDICTION API                                                  │
│                                                                 │
│ Tool: prediction/api.py (FastAPI)                              │
│ Endpoint: POST /predict                                         │
│                                                                 │
│ Input:                                                          │
│ {                                                               │
│   "gates": 100000,                                              │
│   "nets": 90000                                                 │
│ }                                                               │
│                                                                 │
│ Output:                                                         │
│ {                                                               │
│   "cpu_percent": 150.5,                                         │
│   "memory_mb": 12288,                                           │
│   "runtime_seconds": 450                                        │
│ }                                                               │
└─────────────────────────────────────────────────────────────────┘
```

---

## Flow 2: Resource Tracking During Job Execution

### Real-Time Monitoring Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│ COMPUTE NODE (where job runs)                                  │
│                                                                 │
│ ┌─────────────────────────────────────────────────────────────┐ │
│ │ Singularity Container                                       │ │
│ │                                                             │ │
│ │ ┌─────────────────────────────────────────────────────────┐ │ │
│ │ │ OpenROAD Process (PID: 12345)                          │ │ │
│ │ │ - Running inside container                              │ │ │
│ │ │ - Memory limit set by SLURM cgroups                     │ │ │
│ │ │ - CPU allocation controlled by SLURM                    │ │ │
│ │ └─────────────────────────────────────────────────────────┘ │ │
│ │                                                             │ │
│ │ Container Resources:                                        │ │
│ │ - Isolated filesystem (overlay)                            │ │
│ │ - Shared /shared mount (EFS)                               │ │
│ │ - Network namespace                                         │ │
│ └─────────────────────────────────────────────────────────────┘ │
│                                                                 │
│ ┌─────────────────────────────────────────────────────────────┐ │
│ │ SLURM cgroups (Linux Control Groups)                       │ │
│ │                                                             │ │
│ │ /sys/fs/cgroup/memory/slurm/uid_1000/job_12345/            │ │
│ │ - memory.limit_in_bytes = 12884901888 (12GB)               │ │
│ │ - memory.usage_in_bytes = 10737418240 (10GB current)       │ │
│ │ - memory.max_usage_in_bytes = 11811160064 (11GB peak)      │ │
│ │                                                             │ │
│ │ /sys/fs/cgroup/cpu/slurm/uid_1000/job_12345/               │ │
│ │ - cpu.shares = 1024 (relative CPU weight)                  │ │
│ │ - cpuacct.usage = 450000000000 (450 CPU-seconds)           │ │
│ └─────────────────────────────────────────────────────────────┘ │
│                                                                 │
│ ┌─────────────────────────────────────────────────────────────┐ │
│ │ Resource Monitor (monitoring/resource_monitor.py)          │ │
│ │                                                             │ │
│ │ import psutil                                               │ │
│ │                                                             │ │
│ │ while job_running:                                          │ │
│ │     process = psutil.Process(pid)                           │ │
│ │     cpu = process.cpu_percent(interval=1)                   │ │
│ │     memory = process.memory_info().rss / 1024 / 1024       │ │
│ │     io = process.io_counters()                              │ │
│ │     save_metrics(cpu, memory, io)                           │ │
│ │     time.sleep(5)                                           │ │
│ └─────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────────────┐
│ METRICS AGGREGATION                                             │
│                                                                 │
│ Collected every 5 seconds:                                      │
│ - CPU: 145%, 150%, 148%, 152%, 149% → Avg: 148.8%              │
│ - Memory: 10GB, 11GB, 12GB, 11.5GB → Peak: 12GB                │
│ - I/O: Read 500MB, Write 200MB                                 │
│                                                                 │
│ Saved to: data/metrics/job_12345.json                          │
└─────────────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────────────┐
│ SLURM ACCOUNTING (sacct)                                        │
│                                                                 │
│ Stored in: SLURM database (MySQL/MariaDB)                      │
│                                                                 │
│ sacct -j 12345 --format=JobID,MaxRSS,AveCPU,Elapsed            │
│                                                                 │
│ Output:                                                         │
│ JobID    MaxRSS   AveCPU   Elapsed                             │
│ 12345    12288M   148.8%   00:07:30                            │
└─────────────────────────────────────────────────────────────────┘
```

---

## Flow 3: Resource Allocation Adjustment

### Three Mechanisms for Allocation

#### Mechanism 1: Job Submit Plugin (Pre-Allocation)

```
┌─────────────────────────────────────────────────────────────────┐
│ USER SUBMITS JOB                                                │
│                                                                 │
│ $ sbatch --export=DESIGN_GATES=100000 job.sh                   │
└─────────────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────────────┐
│ SLURM CONTROLLER (slurmctld)                                    │
│                                                                 │
│ Location: /opt/slurm/etc/job_submit.lua                        │
│ Tool: slurm/job_submit_dynamic.lua                             │
│                                                                 │
│ function slurm_job_submit(job_desc, part_list, submit_uid)     │
│   -- Read design parameters from environment                    │
│   local gates = job_desc.environment["DESIGN_GATES"]           │
│                                                                 │
│   if gates then                                                 │
│     -- Calculate memory requirement                             │
│     local base_mb = 2000                                        │
│     local per_gate_mb = 0.08                                    │
│     local predicted_mb = base_mb + (gates * per_gate_mb)        │
│     local safe_mb = predicted_mb * 1.2  -- 20% buffer           │
│                                                                 │
│     -- MODIFY job submission BEFORE scheduling                  │
│     job_desc.min_mem_per_node = safe_mb                         │
│                                                                 │
│     slurm.log_info("Adjusted memory: %d MB for %d gates",      │
│                    safe_mb, gates)                              │
│   end                                                           │
│                                                                 │
│   return slurm.SUCCESS                                          │
│ end                                                             │
│                                                                 │
│ Result: Job submitted with 12GB instead of user's 4GB request  │
└─────────────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────────────┐
│ SLURM SCHEDULES JOB                                             │
│ - Allocates 12GB memory                                         │
│ - Allocates 2 CPUs                                              │
│ - Assigns to compute node                                       │
└─────────────────────────────────────────────────────────────────┘
```

**Who initiates:** SLURM controller (automatic)  
**When:** Before job scheduling  
**Syntax:** Lua script modifies `job_desc` structure  
**Mechanism:** SLURM job_submit plugin API  

#### Mechanism 2: SPANK Plugin (Launch-Time Adjustment)

```
┌─────────────────────────────────────────────────────────────────┐
│ JOB ALLOCATED TO COMPUTE NODE                                   │
│ - SLURM has allocated 12GB                                      │
│ - Job about to start                                            │
└─────────────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────────────┐
│ SPANK PLUGIN EXECUTES                                           │
│                                                                 │
│ Location: /opt/slurm/lib/slurm/spank_dynamic_alloc.so          │
│ Source: spank/spank_dynamic_alloc.c                            │
│                                                                 │
│ int slurm_spank_task_post_fork(spank_t sp, int ac, char **av) {│
│   // Called AFTER SLURM allocates, BEFORE process starts       │
│                                                                 │
│   // Get design parameters                                      │
│   char gates_str[64];                                           │
│   spank_getenv(sp, "DESIGN_GATES", gates_str, sizeof(gates));  │
│   long gates = atol(gates_str);                                 │
│                                                                 │
│   // Calculate memory limit                                     │
│   long base_mb = 2000;                                          │
│   long per_gate_mb = 0.08;                                      │
│   long predicted_mb = base_mb + (gates * per_gate_mb);          │
│   long safe_mb = predicted_mb * 1.2;                            │
│                                                                 │
│   // SET PROCESS MEMORY LIMIT (within SLURM allocation)         │
│   struct rlimit rlim;                                           │
│   rlim.rlim_cur = safe_mb * 1024 * 1024;  // Soft limit        │
│   rlim.rlim_max = safe_mb * 1024 * 1024;  // Hard limit        │
│                                                                 │
│   if (setrlimit(RLIMIT_AS, &rlim) == 0) {                      │
│     slurm_info("Set memory limit: %ld MB", safe_mb);           │
│   }                                                             │
│                                                                 │
│   return SLURM_SUCCESS;                                         │
│ }                                                               │
│                                                                 │
│ Result: Process limited to 10GB (within 12GB SLURM allocation) │
└─────────────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────────────┐
│ PROCESS STARTS WITH LIMITS                                      │
│ - SLURM cgroup limit: 12GB (enforced by kernel)                │
│ - Process rlimit: 10GB (enforced by kernel)                    │
│ - Effective limit: 10GB (whichever is lower)                   │
└─────────────────────────────────────────────────────────────────┘
```

**Who initiates:** SLURM slurmd daemon (automatic)  
**When:** After allocation, before process starts  
**Syntax:** C code using setrlimit() system call  
**Mechanism:** SPANK plugin API + Linux rlimits  

#### Mechanism 3: Elastic Jobs (Runtime Scaling)

```
┌─────────────────────────────────────────────────────────────────┐
│ USER SUBMITS ELASTIC JOB                                        │
│                                                                 │
│ $ sbatch --nodes=2-10 elastic_job.sh                           │
│           ↑      ↑                                              │
│           min    max nodes                                      │
└─────────────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────────────┐
│ JOB STARTS WITH MINIMUM NODES                                   │
│ - Allocated: 2 nodes                                            │
│ - Total memory: 2 × 64GB = 128GB                                │
│ - Total CPUs: 2 × 16 = 32 CPUs                                  │
└─────────────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────────────┐
│ SLURM MONITORS CLUSTER STATE                                    │
│ - More nodes become available                                   │
│ - Job's partition allows elastic scaling                        │
│ - Job is still running                                          │
└─────────────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────────────┐
│ SLURM GROWS JOB (Automatic)                                     │
│                                                                 │
│ Mechanism: PMIx (Process Management Interface)                  │
│                                                                 │
│ 1. SLURM allocates additional nodes (3 more)                    │
│ 2. PMIx notifies MPI application                                │
│ 3. MPI spawns new processes on new nodes                        │
│ 4. Application redistributes work                               │
│                                                                 │
│ New allocation:                                                 │
│ - Nodes: 5 (grew from 2)                                        │
│ - Total memory: 5 × 64GB = 320GB                                │
│ - Total CPUs: 5 × 16 = 80 CPUs                                  │
└─────────────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────────────┐
│ APPLICATION ADAPTS                                              │
│                                                                 │
│ from mpi4py import MPI                                          │
│                                                                 │
│ comm = MPI.COMM_WORLD                                           │
│ while work_remaining:                                           │
│     size = comm.Get_size()  # Re-check (may have changed!)     │
│     rank = comm.Get_rank()                                      │
│                                                                 │
│     # Redistribute work across current processes                │
│     my_work = distribute_work(total_work, size, rank)           │
│     process(my_work)                                            │
└─────────────────────────────────────────────────────────────────┘
```

**Who initiates:** SLURM scheduler (automatic based on availability)  
**When:** During job execution  
**Syntax:** `--nodes=min-max` in sbatch  
**Mechanism:** PMIx + MPI dynamic processes  

---

## Flow 4: Container Resource Management

### Singularity Container Resource Isolation

```
┌─────────────────────────────────────────────────────────────────┐
│ HOST SYSTEM (Compute Node)                                      │
│                                                                 │
│ ┌─────────────────────────────────────────────────────────────┐ │
│ │ SLURM cgroups (Outer Limit)                                 │ │
│ │                                                             │ │
│ │ /sys/fs/cgroup/memory/slurm/uid_1000/job_12345/            │ │
│ │ memory.limit_in_bytes = 12GB  ← SLURM enforces this        │ │
│ │                                                             │ │
│ │ ┌─────────────────────────────────────────────────────────┐ │ │
│ │ │ Singularity Container                                   │ │ │
│ │ │                                                         │ │ │
│ │ │ Container inherits cgroup limits from SLURM             │ │ │
│ │ │ - No separate cgroup (uses parent)                      │ │ │
│ │ │ - Shares memory limit with host process                 │ │ │
│ │ │                                                         │ │ │
│ │ │ ┌─────────────────────────────────────────────────────┐ │ │ │
│ │ │ │ OpenROAD Process (Inside Container)                │ │ │ │
│ │ │ │                                                     │ │ │ │
│ │ │ │ Process rlimits (Inner Limit):                     │ │ │ │
│ │ │ │ RLIMIT_AS = 10GB  ← SPANK sets this                │ │ │ │
│ │ │ │                                                     │ │ │ │
│ │ │ │ Effective limit: min(12GB, 10GB) = 10GB            │ │ │ │
│ │ │ │                                                     │ │ │ │
│ │ │ │ If process tries to allocate > 10GB:               │ │ │ │
│ │ │ │ → malloc() returns NULL                            │ │ │ │
│ │ │ │ → Process handles gracefully or crashes            │ │ │ │
│ │ │ └─────────────────────────────────────────────────────┘ │ │ │
│ │ │                                                         │ │ │
│ │ │ Filesystem:                                             │ │ │
│ │ │ - / (root): Container image (read-only)                 │ │ │
│ │ │ - /tmp: Overlay (writable, ephemeral)                   │ │ │
│ │ │ - /shared: Bind mount from host (EFS)                   │ │ │
│ │ │ - /home: Bind mount from host                           │ │ │
│ │ └─────────────────────────────────────────────────────────┘ │ │
│ └─────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘

Resource Hierarchy:
1. SLURM cgroup (12GB) ← Outer limit, kernel-enforced
2. Process rlimit (10GB) ← Inner limit, kernel-enforced
3. Container inherits both ← No separate limit
4. Effective: 10GB (most restrictive)
```

### How Singularity Interacts with SLURM

```bash
# Job script
#!/bin/bash
#SBATCH --mem=12G          # SLURM allocates 12GB
#SBATCH --cpus-per-task=4  # SLURM allocates 4 CPUs

# SLURM creates cgroup BEFORE container starts
# /sys/fs/cgroup/memory/slurm/uid_1000/job_12345/
# memory.limit_in_bytes = 12884901888 (12GB)

# SPANK plugin runs (sets rlimit to 10GB)

# Singularity starts
singularity exec openroad.sif openroad design.tcl

# Container process:
# - Runs in SLURM's cgroup (inherits 12GB limit)
# - Has rlimit of 10GB (set by SPANK)
# - Cannot exceed 10GB (rlimit is lower)
# - If it tries, malloc fails or OOM killer activates
```

### Storage Resources in Container

```
Container Storage Layers:

1. Image Layer (Read-Only)
   /opt/openroad/bin/openroad
   /usr/lib/...
   Source: openroad.sif (SquashFS)

2. Overlay Layer (Writable, Ephemeral)
   /tmp/singularity-overlay-XXXXX
   - Temporary files
   - Process working directory
   - Deleted when container exits

3. Bind Mounts (Shared with Host)
   /shared → /shared (EFS on AWS)
   - Design files
   - Results
   - Logs
   - Persistent across jobs

Storage Tracking:
- SLURM doesn't limit container storage directly
- EFS quota managed by AWS
- Local disk limited by node capacity
- Monitor via: df -h /shared
```

---

## Summary: Three Allocation Strategies

| Strategy | When | Who Initiates | Mechanism | Can Change Runtime? |
|----------|------|---------------|-----------|---------------------|
| **Job Submit Plugin** | Before scheduling | SLURM controller | Lua script modifies job_desc | ❌ No |
| **SPANK Plugin** | After allocation, before start | SLURM slurmd | C code sets rlimits | ❌ No |
| **Elastic Jobs** | During execution | SLURM scheduler | PMIx + MPI | ✅ Yes (nodes only) |

### Key Takeaways

1. **Logs collected by:** `monitoring/resource_monitor.py` (psutil) + `monitoring/openroad_log_parser.py`
2. **Logs saved to:** `data/metrics/job_<id>.json` → SQLite database
3. **Predictions made by:** `prediction/train_model.py` (Ridge regression) → `prediction/api.py` (FastAPI)
4. **Resources tracked via:** SLURM cgroups + psutil + sacct
5. **Allocations adjusted by:** Job submit plugin (pre) + SPANK plugin (launch) + Elastic jobs (runtime)
6. **Container resources:** Inherit SLURM cgroups, no separate limits, bind mounts for shared storage

