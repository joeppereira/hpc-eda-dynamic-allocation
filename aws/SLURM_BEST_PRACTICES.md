# SLURM Configuration Best Practices

## Overview

SLURM (Simple Linux Utility for Resource Management) is highly configurable. This guide covers best practices learned from AWS EDA samples and production HPC deployments, specifically for EDA workloads and resource optimization.

---

## Table of Contents

1. [Core Configuration Files](#core-configuration-files)
2. [Memory-Based Scheduling](#memory-based-scheduling)
3. [Auto-Scaling Configuration](#auto-scaling-configuration)
4. [Partition (Queue) Design](#partition-queue-design)
5. [Job Priority and Fair Share](#job-priority-and-fair-share)
6. [License Management](#license-management)
7. [Accounting and Logging](#accounting-and-logging)
8. [Performance Tuning](#performance-tuning)
9. [SPANK Plugin Integration](#spank-plugin-integration)
10. [Common Pitfalls](#common-pitfalls)

---

## Core Configuration Files

### File Locations (ParallelCluster)

```
/opt/slurm/etc/
├── slurm.conf                    # Main SLURM configuration
├── slurmdbd.conf                 # Accounting database config
├── plugstack.conf                # SPANK plugin configuration
├── gres.conf                     # Generic resources (GPUs, licenses)
├── topology.conf                 # Network topology (optional)
└── pcluster/
    ├── slurm_parallelcluster_*.conf  # ParallelCluster managed
    └── custom_slurm_settings_include_file_slurm.conf  # Custom settings
```

### Configuration Hierarchy

ParallelCluster uses a layered approach:

```
1. Base slurm.conf (ParallelCluster managed - DO NOT EDIT)
   ↓
2. ParallelCluster dynamic configs (auto-generated)
   ↓
3. Custom settings include file (YOUR CUSTOMIZATIONS)
   ↓
4. CustomSlurmSettings (via cluster config YAML)
```

**Best Practice**: Use `CustomSlurmSettings` in cluster config, not direct file edits

---

## Memory-Based Scheduling

### Why It Matters for EDA

EDA tools (OpenROAD, Cadence, Synopsys) have **unpredictable memory usage**:
- Synthesis: 2-8GB per million gates
- Placement: 10-50GB for large designs
- Routing: 20-100GB+ for complex designs

**Without memory-based scheduling**: Jobs can OOM-kill and crash nodes

### Enable Memory-Based Scheduling

```yaml
# In ParallelCluster config
slurm:
  ParallelClusterConfig:
    ClusterConfig:
      Scheduling:
        SlurmSettings:
          EnableMemoryBasedScheduling: true
```

This sets in `slurm.conf`:
```
SelectType=select/cons_tres
SelectTypeParameters=CR_CPU_Memory
```

### What This Does

**Without memory scheduling**:
```bash
# Job requests 4 CPUs, SLURM allocates 4 CPUs
sbatch --cpus-per-task=4 job.sh

# Problem: Job uses 64GB RAM, but node only has 32GB
# Result: OOM killer terminates job
```

**With memory scheduling**:
```bash
# Job requests 4 CPUs and 64GB RAM
sbatch --cpus-per-task=4 --mem=64G job.sh

# SLURM checks: Does node have 64GB available?
# If yes: Schedule job
# If no: Wait for node with enough memory
```

### Best Practices

1. **Always specify memory** in job submissions:
   ```bash
   #SBATCH --mem=32G          # Total memory for job
   # OR
   #SBATCH --mem-per-cpu=8G   # Memory per CPU
   ```

2. **Set realistic defaults** in partition config:
   ```
   DefMemPerCPU=4096  # 4GB per CPU default
   MaxMemPerCPU=16384 # 16GB per CPU maximum
   ```

3. **Configure node memory** accurately:
   ```
   # In slurm.conf (ParallelCluster does this automatically)
   NodeName=compute-dy-c5-4xlarge-[1-10] RealMemory=30720  # 32GB - 1.28GB for OS
   ```

4. **Use our ML predictions** to set optimal memory:
   ```python
   # Our job optimizer does this automatically
   predicted_memory = predict_memory(design_features)
   sbatch_args = f"--mem={int(predicted_memory * 1.1)}G"  # 10% buffer
   ```

---

## Auto-Scaling Configuration

### Key Parameters

```yaml
slurm:
  ParallelClusterConfig:
    ClusterConfig:
      Scheduling:
        SlurmSettings:
          ScaledownIdletime: 10  # Minutes before idle node terminates
          SuspendTime: 300       # Seconds before marking node as suspended
          ResumeTimeout: 600     # Seconds to wait for node to boot
```

### ScaledownIdletime (Critical for Cost)

**What it does**: Terminates idle compute nodes after N minutes

**AWS EDA recommendation**: 10 minutes (balance cost vs responsiveness)

**Our recommendation**: 
- **Development**: 5 minutes (save costs during testing)
- **Production**: 10 minutes (standard)
- **Batch workloads**: 15-20 minutes (reduce churn)

**Example cost impact**:
```
c5.4xlarge = $0.68/hour

ScaledownIdletime=5:  Idle 5 min  = $0.06 wasted
ScaledownIdletime=10: Idle 10 min = $0.11 wasted
ScaledownIdletime=60: Idle 60 min = $0.68 wasted

With 10 nodes cycling 20 times/day:
  5 min:  $12/day saved vs 60 min
  10 min: $10/day saved vs 60 min
```

### SuspendTime

**What it does**: How long to wait before marking node as "suspended" (powered down)

**Best practice**: 300 seconds (5 minutes)
- Too short: Nodes marked down prematurely during boot
- Too long: Delays in detecting failed nodes

### ResumeTimeout

**What it does**: How long to wait for node to boot before giving up

**Best practice**: 600 seconds (10 minutes)
- AWS EC2 boot: 2-5 minutes typical
- Custom AMI with large software: 5-10 minutes
- Network issues: Need buffer

**Our case** (OpenROAD + SPANK plugin):
```yaml
ResumeTimeout: 900  # 15 minutes
# Reason: Custom AMI with OpenROAD, PDKs, SPANK plugin
```

### Node Weights (Cost Optimization)

**ParallelCluster 3.7+** supports node weights to prefer cheaper instances:

```yaml
slurm:
  ParallelClusterConfig:
    ClusterConfig:
      Scheduling:
        SlurmSettings:
          CustomSlurmSettings:
            - NodeName: compute-dy-c5-4xlarge-[1-10]
              Weight: 100  # Prefer these (cheaper)
            - NodeName: compute-dy-c5-9xlarge-[1-5]
              Weight: 200  # Use these only if needed (expensive)
```

**How it works**: SLURM schedules jobs on lowest weight nodes first

---

## Partition (Queue) Design

### Single Partition (Our Approach - Simple)

```yaml
# Minimal config for testing
slurm:
  ParallelClusterConfig:
    ClusterConfig:
      Scheduling:
        SlurmQueues:
          - Name: compute
            ComputeResources:
              - Name: openroad-nodes
                InstanceType: c5.4xlarge
                MinCount: 0
                MaxCount: 10
```

**Pros**:
- ✅ Simple configuration
- ✅ Easy to understand
- ✅ Good for single-user testing

**Cons**:
- ⚠️ No priority differentiation
- ⚠️ All jobs treated equally

### Multi-Partition (AWS EDA Approach - Production)

```yaml
slurm:
  ParallelClusterConfig:
    ClusterConfig:
      Scheduling:
        SlurmQueues:
          - Name: interactive
            ComputeResources:
              - Name: interactive-nodes
                InstanceType: c5.2xlarge
                MinCount: 0
                MaxCount: 5
            # Higher priority for interactive work
            
          - Name: batch
            ComputeResources:
              - Name: batch-nodes
                InstanceType: c5.4xlarge
                MinCount: 0
                MaxCount: 20
            # Lower priority for batch jobs
            
          - Name: large-memory
            ComputeResources:
              - Name: memory-nodes
                InstanceType: r5.4xlarge  # Memory-optimized
                MinCount: 0
                MaxCount: 5
```

**Pros**:
- ✅ Priority differentiation
- ✅ Resource specialization
- ✅ Better for multi-user

**Cons**:
- ⚠️ More complex
- ⚠️ Requires tuning

### Partition Priority

```yaml
slurm:
  ParallelClusterConfig:
    ClusterConfig:
      Scheduling:
        SlurmSettings:
          CustomSlurmSettings:
            - PartitionName: interactive
              PriorityTier: 100
              Default: YES
            - PartitionName: batch
              PriorityTier: 50
            - PartitionName: large-memory
              PriorityTier: 75
```

**How it works**:
- Higher `PriorityTier` = higher priority
- Interactive jobs preempt batch jobs
- Users can specify partition: `sbatch -p large-memory job.sh`

### Best Practice: Start Simple, Add Complexity

**Phase 1** (Testing): Single partition
**Phase 2** (Production): Add interactive partition
**Phase 3** (Scale): Add specialized partitions (memory, GPU, etc.)

---

## Job Priority and Fair Share

### Priority Calculation

SLURM calculates job priority using multiple factors:

```
Priority = 
    (PriorityWeightPartition × PartitionPriority) +
    (PriorityWeightFairshare × FairshareScore) +
    (PriorityWeightAge × AgeScore) +
    (PriorityWeightQOS × QOSPriority) +
    (PriorityWeightJobSize × JobSizeScore)
```

### AWS EDA Default Configuration

```
PriorityType=priority/multifactor
PriorityWeightPartition=100000  # Partition is most important
PriorityWeightFairshare=10000   # Fair share second
PriorityWeightQOS=10000         # QOS third
PriorityWeightAge=1000          # Age (FIFO) fourth
PriorityWeightJobSize=0         # Job size not considered
```

**Why this works**:
1. **Partition priority dominates** - Interactive jobs always beat batch
2. **Fair share prevents monopolization** - Heavy users get lower priority
3. **Age ensures FIFO within priority** - Older jobs go first
4. **Job size ignored** - Don't penalize large jobs

### Fair Share Configuration

**Enable fair share**:
```yaml
slurm:
  ParallelClusterConfig:
    ClusterConfig:
      Scheduling:
        SlurmSettings:
          CustomSlurmSettings:
            - PriorityType: priority/multifactor
              PriorityDecayHalfLife: 7-0  # 7 days
              FairShareDampeningFactor: 5
```

**Configure accounts** (on head node):
```bash
# Create accounts
sacctmgr add account project1 Description="Project 1"
sacctmgr add account project2 Description="Project 2"

# Set fair share weights
sacctmgr modify account project1 set fairshare=80
sacctmgr modify account project2 set fairshare=20

# Add users to accounts
sacctmgr add user alice account=project1
sacctmgr add user bob account=project2
```

**How it works**:
- Project1 gets 80% of resources (4× more than Project2)
- If Project1 overuses, their jobs get lower priority
- If Project2 underuses, their jobs get higher priority
- Balances over time (7-day half-life)

### Our Use Case (Single User)

**We don't need fair share** for testing, but enable for production:

```yaml
# Phase 1: Testing (skip fair share)
# Just use default FIFO

# Phase 2: Production (enable fair share)
slurm:
  ParallelClusterConfig:
    ClusterConfig:
      Scheduling:
        SlurmSettings:
          CustomSlurmSettings:
            - PriorityType: priority/multifactor
              PriorityWeightAge: 10000  # FIFO within priority
```

---

## License Management

### Why License Management Matters

Commercial EDA tools (Cadence, Synopsys, Mentor) use **floating licenses**:
- Limited number of licenses (expensive: $50K-500K per license)
- Multiple users compete for licenses
- Jobs fail if no licenses available
- Need to prevent license monopolization

### Configure Licenses in SLURM

```yaml
slurm:
  Licenses:
    vcs:      # Synopsys VCS (simulation)
      Count: 800
      Server: license-server.company.com
      Port: 27000
    calibre:  # Mentor Calibre (verification)
      Count: 50
      Server: license-server.company.com
      Port: 27001
```

This adds to `slurm.conf`:
```
Licenses=vcs:800,calibre:50
```

### Request Licenses in Jobs

```bash
#!/bin/bash
#SBATCH --job-name=simulation
#SBATCH --licenses=vcs:4      # Request 4 VCS licenses
#SBATCH --mem=16G
#SBATCH --time=02:00:00

# Run simulation (uses 4 VCS licenses)
vcs -full64 design.v
```

**What happens**:
1. Job requests 4 VCS licenses
2. SLURM checks: Are 4 licenses available?
3. If yes: Job starts, SLURM decrements license count
4. If no: Job waits in queue until licenses free up
5. When job completes: SLURM increments license count

### License Tracking

```bash
# View license usage
scontrol show lic

# Output:
LicenseName=vcs
    Total=800 Used=456 Free=344 Reserved=0 Remote=no

LicenseName=calibre
    Total=50 Used=48 Free=2 Reserved=0 Remote=no
```

### Our Use Case (OpenROAD)

**We don't need license management** - OpenROAD is open source (free)

**Skip this configuration** unless using commercial tools later

---

## Accounting and Logging

### SLURM Accounting Database (slurmdbd)

**Purpose**: Track job history, user quotas, resource usage

**What it stores**:
- Job metadata (ID, user, partition, submit time)
- Resource requests (CPUs, memory, time limit)
- Resource usage (CPU time, max memory, exit code)
- Job states (pending, running, completed, failed)

**What it DOESN'T store** (why we need custom database):
- ❌ Per-stage metrics (placement, routing, etc.)
- ❌ Design features (cell count, frequency, etc.)
- ❌ Tool-specific data (OpenROAD stages, bottlenecks)

### Enable SLURM Accounting

**Option 1: External slurmdbd (Recommended for Production)**

```yaml
slurm:
  ParallelClusterConfig:
    Slurmdbd:
      SlurmdbdStackName: my-slurmdbd-stack  # Created separately
```

**Option 2: Embedded slurmdbd (Legacy, not recommended)**

```yaml
slurm:
  ParallelClusterConfig:
    Database:
      DatabaseStackName: my-database-stack
```

### Query Accounting Data

```bash
# Show all jobs today
sacct -S today

# Show specific job details
sacct -j 12345 --format=JobID,JobName,Partition,State,Elapsed,MaxRSS

# Show user usage
sreport user top start=2025-11-01 end=2025-11-30

# Show cluster utilization
sreport cluster utilization start=2025-11-01
```

### Our Hybrid Approach

**Enable SLURM accounting** (free, useful for debugging):
```yaml
slurm:
  ParallelClusterConfig:
    Slurmdbd:
      SlurmdbdStackName: hpc-slurmdbd
```

**PLUS custom database** (required for ML):
```yaml
# RDS PostgreSQL for per-stage metrics
Database:
  Host: hpc-metrics.xxxxx.rds.amazonaws.com
  Port: 5432
  Name: hpc_metrics
```

**Why both?**
- SLURM accounting: Job-level tracking, quotas, debugging
- Custom database: Per-stage metrics, design features, ML training

**Cost**: SLURM accounting is free, custom DB is ~$25/month

---

## Performance Tuning

### slurmctld (Controller) Tuning

```yaml
slurm:
  ParallelClusterConfig:
    ClusterConfig:
      Scheduling:
        SlurmSettings:
          CustomSlurmSettings:
            # Increase scheduling frequency
            - SchedulerTimeSlice: 30  # Seconds between scheduling cycles
            
            # Batch scheduling for efficiency
            - batch_sched_delay: 3    # Seconds to batch job submissions
            
            # Increase max job count
            - MaxJobCount: 100000     # Max jobs in system
            
            # Faster job start
            - MessageTimeout: 60      # Seconds to wait for node response
```

### slurmd (Compute Node) Tuning

```yaml
slurm:
  ParallelClusterConfig:
    ClusterConfig:
      Scheduling:
        SlurmSettings:
          CustomSlurmSettings:
            # Health check frequency
            - SlurmdTimeout: 300      # Seconds before marking node down
            
            # Faster job launch
            - LaunchParameters: enable_nss_slurm  # Use SLURM's NSS module
            
            # Prolog/Epilog timeouts
            - PrologEpilogTimeout: 300  # Seconds for prolog/epilog scripts
```

### Network Tuning

```yaml
slurm:
  ParallelClusterConfig:
    ClusterConfig:
      Scheduling:
        SlurmSettings:
          CustomSlurmSettings:
            # Communication parameters
            - TCPTimeout: 10          # Seconds for TCP connections
            - MessageTimeout: 60      # Seconds for message responses
            
            # Reduce fanout issues
            - TreeWidth: 50           # Max children per node in tree
```

### Our Tuning (EDA Workloads)

```yaml
slurm:
  ParallelClusterConfig:
    ClusterConfig:
      Scheduling:
        SlurmSettings:
          CustomSlurmSettings:
            # EDA jobs are long-running, don't need fast scheduling
            - SchedulerTimeSlice: 60
            
            # SPANK plugin needs time to initialize
            - PrologEpilogTimeout: 600  # 10 minutes
            
            # Large memory jobs need time to allocate
            - MessageTimeout: 120
```

---

## SPANK Plugin Integration

### Configure SPANK Plugin

**1. Create plugstack.conf**:
```bash
# /opt/slurm/etc/plugstack.conf
required /shared/spank/spank_monitor.so
```

**2. Deploy via CustomActions**:
```yaml
slurm:
  ParallelClusterConfig:
    ClusterConfig:
      HeadNode:
        CustomActions:
          OnNodeConfigured:
            Script: s3://bucket/scripts/setup-spank-head.sh
      Scheduling:
        SlurmQueues:
          - Name: compute
            CustomActions:
              OnNodeConfigured:
                Script: s3://bucket/scripts/setup-spank-compute.sh
```

**3. Setup script** (`setup-spank-compute.sh`):
```bash
#!/bin/bash
# Copy SPANK plugin from shared storage
cp /shared/spank/spank_monitor.so /usr/lib64/slurm/

# Create plugstack.conf
cat > /opt/slurm/etc/plugstack.conf <<EOF
required /usr/lib64/slurm/spank_monitor.so
EOF

# Restart slurmd to load plugin
systemctl restart slurmd
```

### Verify SPANK Plugin

```bash
# Check if plugin loaded
scontrol show config | grep -i spank

# Should show:
PlugStackConfig = /opt/slurm/etc/plugstack.conf

# Test with dummy job
sbatch --wrap="sleep 10"

# Check plugin output
ls /shared/metrics/job_*.json
```

### SPANK Plugin Best Practices

1. **Fail gracefully**: Plugin errors shouldn't kill jobs
   ```c
   if (error) {
       slurm_error("SPANK: Error occurred, continuing job");
       return SLURM_SUCCESS;  // Don't fail job
   }
   ```

2. **Minimal overhead**: Keep monitoring lightweight
   ```c
   // Sample every 1 second, not every 100ms
   sleep(1);
   ```

3. **Thread safety**: Use proper locking
   ```c
   pthread_mutex_lock(&metrics_lock);
   update_metrics();
   pthread_mutex_unlock(&metrics_lock);
   ```

4. **Clean up resources**: Always free memory
   ```c
   int slurm_spank_exit(spank_t sp, int ac, char **av) {
       free(metrics_buffer);
       close(metrics_file);
       return SLURM_SUCCESS;
   }
   ```

---

## Common Pitfalls

### 1. Not Specifying Memory

**Problem**:
```bash
sbatch --cpus-per-task=4 job.sh  # No --mem specified
```

**Result**: Job gets default memory (often too little), OOM kills job

**Solution**:
```bash
sbatch --cpus-per-task=4 --mem=32G job.sh
```

### 2. ScaledownIdletime Too Long

**Problem**:
```yaml
ScaledownIdletime: 60  # 1 hour
```

**Result**: Idle nodes run for 1 hour, wasting $0.68/hour per node

**Solution**:
```yaml
ScaledownIdletime: 10  # 10 minutes (AWS EDA recommendation)
```

### 3. Not Using Memory-Based Scheduling

**Problem**: Jobs scheduled by CPU only, memory not considered

**Result**: Multiple jobs on same node exceed available memory, OOM kills

**Solution**:
```yaml
EnableMemoryBasedScheduling: true
```

### 4. Editing slurm.conf Directly

**Problem**: ParallelCluster overwrites `slurm.conf` on updates

**Solution**: Use `CustomSlurmSettings` in cluster config

### 5. SPANK Plugin Crashes Jobs

**Problem**: Plugin error causes job to fail

**Solution**: Always return `SLURM_SUCCESS`, log errors separately

### 6. Too Many Partitions

**Problem**: 10+ partitions, complex configuration, hard to manage

**Solution**: Start with 1-2 partitions, add more only if needed

### 7. Not Enabling Accounting

**Problem**: No job history, can't debug failures

**Solution**: Enable slurmdbd (free, useful)

### 8. Insufficient ResumeTimeout

**Problem**: Nodes marked down before finishing boot

**Solution**: Set `ResumeTimeout: 900` (15 minutes) for custom AMIs

---

## Summary: Our SLURM Configuration

### Minimal Configuration (Phase 1: Testing)

```yaml
Region: us-east-1
Image:
  Os: alinux2

HeadNode:
  InstanceType: c5.xlarge

Scheduling:
  Scheduler: slurm
  SlurmQueues:
    - Name: compute
      ComputeResources:
        - Name: openroad
          InstanceType: c5.4xlarge
          MinCount: 0
          MaxCount: 4
  SlurmSettings:
    ScaledownIdletime: 5  # Fast scale-down for testing
    EnableMemoryBasedScheduling: true
    CustomSlurmSettings:
      - PrologEpilogTimeout: 600  # SPANK plugin needs time

SharedStorage:
  - MountDir: /shared
    Name: shared-efs
    StorageType: Efs
```

### Production Configuration (Phase 2: Production)

```yaml
Region: us-east-1
Image:
  Os: alinux2

HeadNode:
  InstanceType: c5.xlarge
  CustomActions:
    OnNodeConfigured:
      Script: s3://bucket/scripts/setup-head-node.sh

Scheduling:
  Scheduler: slurm
  SlurmQueues:
    - Name: compute
      ComputeResources:
        - Name: openroad
          InstanceType: c5.4xlarge
          MinCount: 0
          MaxCount: 10
      CustomActions:
        OnNodeConfigured:
          Script: s3://bucket/scripts/setup-compute-node.sh
  SlurmSettings:
    ScaledownIdletime: 10
    EnableMemoryBasedScheduling: true
    CustomSlurmSettings:
      - PrologEpilogTimeout: 600
      - ResumeTimeout: 900
      - SchedulerTimeSlice: 60
      - MessageTimeout: 120

slurm:
  ParallelClusterConfig:
    Slurmdbd:
      SlurmdbdStackName: hpc-slurmdbd  # Enable accounting

SharedStorage:
  - MountDir: /shared
    Name: shared-efs
    StorageType: Efs
```

---

## Key Takeaways

1. ✅ **Enable memory-based scheduling** - Critical for EDA workloads
2. ✅ **Set ScaledownIdletime=10** - Balance cost vs responsiveness
3. ✅ **Use CustomSlurmSettings** - Don't edit slurm.conf directly
4. ✅ **Start simple** - Single partition, add complexity later
5. ✅ **Enable accounting** - Free, useful for debugging
6. ✅ **SPANK plugin via CustomActions** - Automated deployment
7. ✅ **Always specify --mem** - Don't rely on defaults
8. ✅ **Test incrementally** - Single node → small cluster → production

## References

- [SLURM Configuration Guide](https://slurm.schedmd.com/slurm.conf.html)
- [ParallelCluster SLURM Settings](https://docs.aws.amazon.com/parallelcluster/latest/ug/Scheduling-v3.html)
- [AWS EDA SLURM Cluster](https://github.com/aws-samples/aws-eda-slurm-cluster)
- [SLURM Accounting](https://slurm.schedmd.com/accounting.html)
- [SPANK Plugin Guide](https://slurm.schedmd.com/spank.html)
