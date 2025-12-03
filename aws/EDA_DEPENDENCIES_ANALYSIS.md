# AWS EDA SLURM Cluster - EDA Dependencies Analysis

## Summary: Is RES the Only EDA Dependency?

**NO** - RES is **optional**, not required. The AWS EDA SLURM cluster is EDA-focused but **tool-agnostic**.

## What "EDA" Means in This Context

"EDA" = **Electronic Design Automation** (chip design workflows)

The repository is called "aws-**eda**-slurm-cluster" because it's **optimized for EDA workloads**, not because it requires specific EDA tools.

## EDA-Specific Features (Not Dependencies)

### 1. License Management ✅
**Purpose**: Manage commercial EDA tool licenses as consumable resources

```yaml
slurm:
  Licenses:
    vcs:        # Synopsys VCS (simulation)
      Count: 800
    ansys:      # Ansys (analysis)
      Count: 1
    calibre:    # Mentor Calibre (verification)
      Count: 50
```

**How it works**:
- SLURM tracks license usage
- Jobs request licenses: `sbatch -L vcs:4 job.sh`
- Jobs wait if licenses unavailable
- Prevents license monopolization

**Is this required?** NO - Optional feature for commercial tools

### 2. Fair Share Scheduling ✅
**Purpose**: Prevent one team/user from monopolizing cluster

```yaml
# Example: Design teams get priority allocation
project1-dv:      # Design Verification team
  fairshare: 80
project1-pd:      # Physical Design team
  fairshare: 10
```

**Is this required?** NO - Optional for multi-team environments

### 3. High-Performance File Systems ✅
**Purpose**: EDA workloads need fast I/O (reading/writing large design files)

Supported:
- FSx for Lustre (parallel file system)
- FSx for NetApp ONTAP (NFS with high IOPS)
- FSx for OpenZFS (high-performance ZFS)

**Is this required?** NO - Can use basic EFS or EBS

### 4. Memory-Based Scheduling ✅
**Purpose**: EDA jobs often need specific memory amounts

```bash
sbatch --mem=64G job.sh  # Request 64GB RAM
```

**Is this required?** YES - But this is standard SLURM, not EDA-specific

### 5. Spot Instance Handling ✅
**Purpose**: Save costs on long-running EDA jobs

- Handles spot terminations gracefully
- Checkpoints jobs
- Requeues interrupted jobs

**Is this required?** NO - Can use on-demand only

## RES Integration (Optional)

### What is RES?
**RES** = **Research and Engineering Studio**
- Open-source web portal for virtual desktops
- Provides DCV (remote desktop) instances
- User self-service provisioning
- NOT specific to EDA

### RES Features
- Virtual desktop management
- User authentication (Active Directory/Keycloak)
- File system management
- Project-based access control

### RES Integration with SLURM
When you specify `RESStackName` in config:
1. Automatically configures RES desktops as SLURM login nodes
2. Mounts shared file systems on desktops
3. Syncs users/groups from Active Directory
4. Adds security groups for cluster access

### Is RES Required?
**NO** - RES is completely optional

**Without RES, you can**:
- SSH directly to head node
- Use ParallelCluster login nodes
- Use your own virtual desktops
- Submit jobs from any configured host

**RES is useful if you want**:
- Web-based desktop provisioning
- User self-service
- Integrated file system management
- Active Directory integration

## What IS Required?

### Absolute Requirements
1. ✅ **AWS Account** with appropriate permissions
2. ✅ **VPC** with subnets
3. ✅ **EC2 Key Pair** for SSH access
4. ✅ **ParallelCluster CLI** (installed ✓)
5. ✅ **S3 Bucket** for scripts/configs

### Optional Components
- ❌ RES (virtual desktops)
- ❌ EDA tools (Cadence, Synopsys, etc.)
- ❌ License servers
- ❌ Active Directory
- ❌ Custom AMIs
- ❌ FSx file systems (can use EFS)
- ❌ Slurm accounting database

## Our Project's EDA Dependency

### What We Actually Need

**EDA Tool**: OpenROAD (open-source digital design flow)

**Why OpenROAD?**
- ✅ Open source (no licenses)
- ✅ Available in Docker
- ✅ Real EDA workload characteristics
- ✅ Multiple stages (synthesis, placement, routing)
- ✅ Realistic resource usage patterns

**How We Use It**:
```bash
# Run OpenROAD in Docker
docker run openroad/flow-ubuntu openroad -version

# Or on SLURM cluster
sbatch openroad_job.sh
```

### Our Dependencies
```
AWS ParallelCluster (SLURM)
    ↓
OpenROAD (EDA tool)
    ↓
Our SPANK Plugin (resource monitoring)
    ↓
PostgreSQL (metrics database)
    ↓
ML Model (predictions)
    ↓
FastAPI (prediction service)
```

**RES**: NOT in our dependency chain

## Comparison: AWS EDA Samples vs Our Project

| Feature | AWS EDA Samples | Our Project |
|---------|----------------|-------------|
| **Purpose** | General EDA cluster | Resource optimization |
| **EDA Tools** | Any (Cadence, Synopsys, etc.) | OpenROAD only |
| **RES** | Optional integration | Not used |
| **License Mgmt** | Yes (for commercial tools) | No (OpenROAD is free) |
| **SPANK Plugin** | Not included | Custom monitoring plugin |
| **ML Predictions** | Not included | Core feature |
| **Database** | Optional (accounting) | Required (metrics) |

## What We Can Learn from AWS EDA Samples

### 1. Deployment Best Practices ✅
- CDK-based infrastructure
- CustomActions for node setup
- Security group management
- External slurmdbd configuration

### 2. SLURM Configuration ✅
- Memory-based scheduling
- Auto-scaling settings
- Queue/partition setup
- Accounting database

### 3. File System Setup ✅
- FSx integration patterns
- Mount point configuration
- Security group setup

### 4. User Management ✅
- users_groups.json pattern
- Domain-joined instance setup
- Cron-based sync

### 5. What We DON'T Need ❌
- RES integration
- License management
- Fair share (single user testing)
- Multiple partitions (start simple)

## Recommended Deployment Strategy

### Phase 1: Minimal Cluster (Start Here)
```yaml
# Minimal config - no RES, no licenses, no fancy features
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
    EnableMemoryBasedScheduling: true

SharedStorage:
  - MountDir: /shared
    Name: shared-efs
    StorageType: Efs
```

**What this gives us**:
- ✅ SLURM cluster
- ✅ Auto-scaling compute nodes
- ✅ Shared storage
- ✅ SPANK plugin support
- ✅ Everything we need

**What this skips**:
- ❌ RES (don't need it)
- ❌ Licenses (OpenROAD is free)
- ❌ Fair share (single user)
- ❌ Multiple queues (keep simple)

### Phase 2: Add Production Features (Later)
- Slurm accounting database
- CloudWatch dashboards
- Multiple instance types
- Spot instances
- FSx for better I/O

### Phase 3: Scale (Much Later)
- Multiple queues
- Fair share scheduling
- License management (if using commercial tools)
- RES integration (if want web portal)

## Key Takeaways

1. **RES is optional** - It's a convenience feature, not a requirement
2. **"EDA" means optimized for chip design** - Not tied to specific tools
3. **We can use the AWS EDA samples** - Just skip RES-related config
4. **Our project is simpler** - We only need OpenROAD + SPANK + database
5. **Start minimal** - Add features as needed

## Next Steps

1. ✅ Use AWS EDA samples as reference (architecture patterns)
2. ✅ Skip RES integration (not needed)
3. ✅ Deploy minimal cluster (basic SLURM + EFS)
4. ✅ Add SPANK plugin via CustomActions
5. ✅ Install OpenROAD on compute nodes
6. ✅ Test with real jobs
7. ⏳ Scale up as needed

## References

- [AWS EDA SLURM Cluster](https://github.com/aws-samples/aws-eda-slurm-cluster)
- [RES Documentation](https://docs.aws.amazon.com/res/latest/ug/)
- [ParallelCluster User Guide](https://docs.aws.amazon.com/parallelcluster/latest/ug/)
- [OpenROAD Project](https://theopenroadproject.org/)
