# Architecture Comparison: Standard vs Learning-Based ParallelCluster

## Deployment Flow Comparison

### Standard AWS EDA SLURM Cluster
```
aws-eda-slurm-cluster (github.com/aws-samples)
├── 1. Clone repository
├── 2. Configure cluster-config.yaml
├── 3. pcluster create-cluster
├── 4. Wait 15-20 minutes
├── 5. SSH to head node
├── 6. Submit jobs manually
└── 7. Monitor with squeue/sacct
```

**Limitations:**
- ❌ No automatic resource optimization
- ❌ Users must guess memory/CPU requirements
- ❌ Jobs fail with OOM if underestimated
- ❌ Resources wasted if overestimated
- ❌ No learning from past executions

### Our Learning-Based System
```
HPC Learning System (This Project)
├── 1. Use existing ParallelCluster
├── 2. Copy deploy_and_test_complete.sh
├── 3. Run single command
├── 4. System installs, tests, learns
├── 5. Results auto-saved to S3
└── 6. Download complete package
```

**Advantages:**
- ✅ Automatic resource optimization
- ✅ Learns from actual job executions
- ✅ Prevents OOM failures
- ✅ Reduces resource waste
- ✅ Improves over time
- ✅ Complete backup to S3

---

## Architecture Diagrams

### Standard ParallelCluster Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         AWS Cloud                                │
│                                                                   │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │                    VPC (10.0.0.0/16)                        │ │
│  │                                                              │ │
│  │  ┌──────────────────────────────────────────────────────┐  │ │
│  │  │              Public Subnet (10.0.0.0/24)             │  │ │
│  │  │                                                        │  │ │
│  │  │  ┌──────────────────────────────────────────────┐    │  │ │
│  │  │  │         Head Node (t3.medium)                │    │  │ │
│  │  │  │  - SLURM Controller (slurmctld)              │    │  │ │
│  │  │  │  - Job Scheduler                             │    │  │ │
│  │  │  │  - User Access (SSH)                         │    │  │ │
│  │  │  │  - NFS Server (/shared)                      │    │  │ │
│  │  │  └──────────────────────────────────────────────┘    │  │ │
│  │  │                        │                              │  │ │
│  │  └────────────────────────┼──────────────────────────────┘  │ │
│  │                           │                                  │ │
│  │  ┌────────────────────────┼──────────────────────────────┐  │ │
│  │  │         Private Subnet (10.0.1.0/24)                  │  │ │
│  │  │                        │                               │  │ │
│  │  │  ┌─────────────────────┴──────────────────────────┐   │  │ │
│  │  │  │    Compute Fleet (Auto Scaling)                │   │  │ │
│  │  │  │                                                 │   │  │ │
│  │  │  │  ┌──────────────┐  ┌──────────────┐           │   │  │ │
│  │  │  │  │ Compute-1    │  │ Compute-2    │  ...      │   │  │ │
│  │  │  │  │ (any type)   │  │ (any type)   │           │   │  │ │
│  │  │  │  │ - slurmd     │  │ - slurmd     │           │   │  │ │
│  │  │  │  │ - Run jobs   │  │ - Run jobs   │           │   │  │ │
│  │  │  │  └──────────────┘  └──────────────┘           │   │  │ │
│  │  │  └─────────────────────────────────────────────────┘   │  │ │
│  │  └──────────────────────────────────────────────────────┘  │ │
│  └──────────────────────────────────────────────────────────┘ │
│                                                                   │
│  ┌──────────────────┐         ┌──────────────────┐             │
│  │   S3 Bucket      │         │   CloudWatch     │             │
│  │   (Logs/Data)    │         │   (Monitoring)   │             │
│  └──────────────────┘         └──────────────────┘             │
└─────────────────────────────────────────────────────────────────┘

User → SSH → Head Node → Submit Job → Compute Nodes → Run Job
```

### Our Learning-Based Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         AWS Cloud (Enhanced)                             │
│                                                                           │
│  ┌────────────────────────────────────────────────────────────────────┐ │
│  │                    VPC (10.0.0.0/16)                                │ │
│  │                                                                      │ │
│  │  ┌──────────────────────────────────────────────────────────────┐  │ │
│  │  │              Public Subnet (10.0.0.0/24)                     │  │ │
│  │  │                                                                │  │ │
│  │  │  ┌──────────────────────────────────────────────────────┐    │  │ │
│  │  │  │         Head Node (t3.medium) - ENHANCED            │    │  │ │
│  │  │  │                                                       │    │  │ │
│  │  │  │  ┌─────────────────────────────────────────────┐    │    │  │ │
│  │  │  │  │  SLURM Controller (slurmctld)               │    │    │  │ │
│  │  │  │  │  + job_submit_learning.lua ◄────────────┐   │    │    │  │ │
│  │  │  │  └─────────────────────────────────────────┘   │    │    │  │ │
│  │  │  │                      │                          │    │    │  │ │
│  │  │  │                      ▼                          │    │    │  │ │
│  │  │  │  ┌─────────────────────────────────────────┐   │    │    │  │ │
│  │  │  │  │  Prediction API (FastAPI:8000)          │   │    │    │  │ │
│  │  │  │  │  - Query historical data                │   │    │    │  │ │
│  │  │  │  │  - ML model predictions                 │   │    │    │  │ │
│  │  │  │  │  - Confidence scoring                   │───┘    │    │  │ │
│  │  │  │  └─────────────────────────────────────────┘        │    │  │ │
│  │  │  │                      │                               │    │  │ │
│  │  │  │                      ▼                               │    │  │ │
│  │  │  │  ┌─────────────────────────────────────────┐        │    │  │ │
│  │  │  │  │  SQLite Database                        │        │    │  │ │
│  │  │  │  │  /shared/hpc_metrics.db                 │        │    │  │ │
│  │  │  │  │  - Job history                          │        │    │  │ │
│  │  │  │  │  - Resource usage                       │        │    │  │ │
│  │  │  │  │  - Design parameters                    │        │    │  │ │
│  │  │  │  └─────────────────────────────────────────┘        │    │  │ │
│  │  │  │                                                      │    │  │ │
│  │  │  │  NFS Server (/shared) - stores all above            │    │  │ │
│  │  │  └──────────────────────────────────────────────────────┘    │  │ │
│  │  │                        │                                      │  │ │
│  │  └────────────────────────┼──────────────────────────────────────┘  │ │
│  │                           │                                          │ │
│  │  ┌────────────────────────┼──────────────────────────────────────┐  │ │
│  │  │         Private Subnet (10.0.1.0/24)                          │  │ │
│  │  │                        │                                       │  │ │
│  │  │  ┌─────────────────────┴──────────────────────────────────┐   │  │ │
│  │  │  │    Compute Fleet (Auto Scaling) - MONITORED           │   │  │ │
│  │  │  │                                                         │   │  │ │
│  │  │  │  ┌──────────────┐  ┌──────────────┐           │   │  │ │
│  │  │  │  │ Compute-1    │  │ Compute-2    │  ...      │   │  │ │
│  │  │  │  │ (any type)   │  │ (any type)   │           │   │  │ │
│  │  │  │  │ - slurmd     │  │ - slurmd     │           │   │  │ │
│  │  │  │  │ - Run jobs   │  │ - Run jobs   │           │   │  │ │
│  │  │  │  └──────────────┘  └──────────────┘           │   │  │ │ │  │  │  ┌──────────────┐  ┌──────────────┐                   │   │  │ │
│  │  │  │  │ Compute-1    │  │ Compute-2    │  ...              │   │  │ │
│  │  │  │  │ (any type)   │  │ (any type)   │                   │   │  │ │
│  │  │  │  │ - slurmd     │  │ - slurmd     │                   │   │  │ │
│  │  │  │  │ - Run jobs   │  │ - Run jobs   │                   │   │  │ │
│  │  │  │  │ - Monitor    │  │ - Monitor    │                   │   │  │ │
│  │  │  │  │   resources  │  │   resources  │                   │   │  │ │
│  │  │  │  └──────┬───────┘  └──────┬───────┘                   │   │  │ │
│  │  │  │         │                  │                           │   │  │ │
│  │  │  │         └──────────┬───────┘                           │   │  │ │
│  │  │  │                    │ Report actual usage               │   │  │ │
│  │  │  │                    ▼                                   │   │  │ │
│  │  │  │         ┌─────────────────────┐                       │   │  │ │
│  │  │  │         │  Metrics Collection │                       │   │  │ │
│  │  │  │         │  → Database         │                       │   │  │ │
│  │  │  │         └─────────────────────┘                       │   │  │ │
│  │  │  └─────────────────────────────────────────────────────────┘   │  │ │
│  │  └──────────────────────────────────────────────────────────────┘  │ │
│  └──────────────────────────────────────────────────────────────────┘ │
│                                                                           │
│  ┌──────────────────────────────────────────────────────────────────┐  │
│  │   S3 Bucket (parallelcluster-xxx-do-not-delete)                  │  │
│  │   /hpc-learning-results/                                          │  │
│  │   ├── learning-results-TIMESTAMP.tar.gz (Complete backup)        │  │
│  │   └── results-TIMESTAMP/                                          │  │
│  │       ├── source_code/ (All code)                                 │  │
│  │       ├── slurm_config/ (SLURM configs)                          │  │
│  │       ├── hpc_metrics.db (Database)                              │  │
│  │       ├── job_*.out (Job outputs)                                │  │
│  │       └── DEPLOYMENT_MANIFEST.txt (Restoration guide)            │  │
│  └──────────────────────────────────────────────────────────────────┘  │
│                                                                           │
│  ┌──────────────────┐         ┌──────────────────┐                     │
│  │   CloudWatch     │         │   IAM Roles      │                     │
│  │   (Monitoring)   │         │   (Permissions)  │                     │
│  └──────────────────┘         └──────────────────┘                     │
└─────────────────────────────────────────────────────────────────────────┘

LEARNING FLOW:
═══════════════
1. User submits job with DESIGN_GATES=50000
2. job_submit plugin intercepts → queries Prediction API
3. API checks database for similar jobs
4. If found: Adjust memory based on history
5. If not: Use defaults, mark for learning
6. Job runs on compute node
7. Actual usage monitored and stored
8. Next similar job uses learned values
```

---

## Data Flow Comparison

### Standard Flow
```
User → Submit Job → SLURM → Compute Node → Done
         (manual    (no      (fixed
          --mem)    learning) resources)
```

### Learning Flow
```
User → Submit Job → job_submit → Prediction API → Database
         (any         plugin      (query          (history)
          --mem)      (intercept) similar jobs)      │
                         │                           │
                         ▼                           │
                    Adjust --mem ◄───────────────────┘
                         │
                         ▼
                    SLURM Queue
                         │
                         ▼
                    Compute Node
                         │
                         ▼
                    Monitor Usage
                         │
                         ▼
                    Store in DB ──────────────────────┐
                         │                             │
                         ▼                             │
                    Next Job Benefits ◄────────────────┘
                    (Better prediction)
```

---

## Key Differences

| Aspect | Standard | Learning-Based |
|--------|----------|----------------|
| **Resource Allocation** | Manual/Static | Automatic/Dynamic |
| **Learning** | None | Continuous |
| **OOM Prevention** | Manual tuning | Automatic |
| **Waste Reduction** | None | Significant |
| **Setup Complexity** | Low | Medium |
| **Long-term Value** | Static | Improves over time |
| **Backup** | Manual | Automatic to S3 |
| **Restoration** | Complex | Documented + Automated |
| **Instance Types** | Any (user choice) | Any (user choice) |
| **Flexibility** | Full | Full (works with any config) |

**Note:** Both systems support any EC2 instance types. The learning system optimizes **memory and CPU allocation within** the chosen instance types, not the instance types themselves. You configure instance types in your ParallelCluster config, and the learning system optimizes how jobs use those resources.

---

## Cost Impact

### Standard Approach
```
Job 1: Request 16GB, Use 4GB → Waste 12GB
Job 2: Request 16GB, Use 4GB → Waste 12GB
Job 3: Request 16GB, Use 4GB → Waste 12GB
...
Total waste: 75% of allocated resources
```

### Learning Approach
```
Job 1: Request 16GB, Use 4GB → Store: "4GB needed"
Job 2: Auto-adjust to 5GB, Use 4GB → Waste 1GB
Job 3: Auto-adjust to 5GB, Use 4GB → Waste 1GB
...
Total waste: 20% of allocated resources
Savings: 55% reduction in wasted resources
```

---

## Summary

Our learning-based system **extends** standard ParallelCluster with:
1. ✅ Intelligent resource allocation
2. ✅ Automatic learning from executions
3. ✅ Complete backup and restoration
4. ✅ Significant cost savings
5. ✅ Zero manual tuning required

It's a **drop-in enhancement** that works with existing ParallelCluster deployments!
