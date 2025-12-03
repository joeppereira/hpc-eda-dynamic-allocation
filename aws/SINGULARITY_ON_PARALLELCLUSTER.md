# Singularity/Apptainer on AWS ParallelCluster

## Executive Summary

**YES, using Singularity matters significantly** - it's actually the **recommended** approach for HPC/SLURM environments.

**AMI Impact**: Minimal - Singularity is easy to install on standard ParallelCluster AMIs via CustomActions scripts.

---

## Quick Answer

### Does Singularity Change AMI Requirements?

**NO** - You can use standard ParallelCluster AMIs and install Singularity via CustomActions.

### Should You Use Singularity?

**YES** - For production SLURM clusters, Singularity is superior to Docker:
- ✅ Native SLURM integration
- ✅ No root privileges required
- ✅ Better security for multi-user
- ✅ Seamless file system access
- ✅ Works with SPANK plugins
- ✅ Near-native performance

---

## Singularity vs Docker on SLURM

### The Problem with Docker on SLURM

```bash
# Docker requires root or docker group
docker run openroad/flow-ubuntu openroad script.tcl

# Issues:
# 1. SLURM users don't have root
# 2. Docker daemon runs as root (security risk)
# 3. File paths get complicated (volume mounts)
# 4. SLURM can't track resources inside container properly
# 5. SPANK plugins can't monitor container processes easily
```

### The Singularity Solution

```bash
# No root required
singularity exec openroad.sif openroad script.tcl

# Benefits:
# 1. Runs as regular user
# 2. No daemon, no security risk
# 3. Automatic file access ($HOME, /shared, etc.)
# 4. SLURM tracks resources correctly
# 5. SPANK plugins work seamlessly
```

---

## AMI Requirements Comparison

### Option 1: Docker on Compute Nodes (Not Recommended)

**AMI Requirements**:
```yaml
# Need to install Docker daemon on every compute node
HeadNode:
  CustomActions:
    OnNodeConfigured:
      Script: s3://bucket/scripts/install-docker-head.sh

Scheduling:
  SlurmQueues:
    - Name: compute
      CustomActions:
        OnNodeConfigured:
          Script: s3://bucket/scripts/install-docker-compute.sh
```

**install-docker-compute.sh**:
```bash
#!/bin/bash
# Install Docker (requires root)
sudo yum install -y docker
sudo systemctl start docker
sudo systemctl enable docker

# Add slurm user to docker group (security risk!)
sudo usermod -aG docker slurm

# Restart slurmd
sudo systemctl restart slurmd
```

**Problems**:
- ❌ Docker daemon on every node (resource overhead)
- ❌ Security risk (docker group = root equivalent)
- ❌ SLURM resource tracking issues
- ❌ SPANK plugin complications
- ❌ File path mapping complexity

### Option 2: Singularity on Compute Nodes (Recommended)

**AMI Requirements**:
```yaml
# Install Singularity on compute nodes
Scheduling:
  SlurmQueues:
    - Name: compute
      CustomActions:
        OnNodeConfigured:
          Script: s3://bucket/scripts/install-singularity.sh
```

**install-singularity.sh**:
```bash
#!/bin/bash
# Install Singularity (simple, no daemon)
sudo yum install -y epel-release
sudo yum install -y singularity-ce

# That's it! No daemon, no group membership needed
```

**Benefits**:
- ✅ Simple installation
- ✅ No daemon (no overhead)
- ✅ Secure (no privilege escalation)
- ✅ SLURM integration works perfectly
- ✅ SPANK plugins work seamlessly

### Option 3: Pre-built AMI with Singularity (Best for Production)

**Create custom AMI once**:
```bash
# 1. Launch instance from ParallelCluster AMI
# 2. Install Singularity
sudo yum install -y epel-release singularity-ce

# 3. Pre-pull container images
singularity pull openroad.sif docker://openroad/flow-ubuntu

# 4. Install other tools
sudo yum install -y python3 fluent-bit

# 5. Create AMI
aws ec2 create-image --instance-id i-xxxxx --name "parallelcluster-openroad-singularity"
```

**Use in cluster config**:
```yaml
slurm:
  ParallelClusterConfig:
    ComputeNodeAmi: ami-xxxxx  # Your custom AMI
```

**Benefits**:
- ✅ Faster node boot (no installation time)
- ✅ Consistent environment
- ✅ Pre-cached container images
- ✅ One-time setup effort

---

## Installation Methods

### Method 1: Install via CustomActions (Recommended for Testing)

**Pros**: 
- ✅ No custom AMI needed
- ✅ Easy to update
- ✅ Works with standard ParallelCluster AMIs

**Cons**:
- ⚠️ Slower node boot (install time)
- ⚠️ Network dependency (yum install)

**Setup**:
```yaml
# cluster-config.yaml
Scheduling:
  SlurmQueues:
    - Name: compute
      ComputeResources:
        - Name: openroad
          InstanceType: c5.4xlarge
          MinCount: 0
          MaxCount: 10
      CustomActions:
        OnNodeConfigured:
          Script: s3://my-bucket/scripts/setup-singularity.sh
```

**setup-singularity.sh**:
```bash
#!/bin/bash
set -e

echo "Installing Singularity..."

# Install EPEL repository
sudo yum install -y epel-release

# Install Singularity
sudo yum install -y singularity-ce

# Verify installation
singularity --version

# Pre-pull OpenROAD container
echo "Pulling OpenROAD container..."
singularity pull /shared/containers/openroad.sif docker://openroad/flow-ubuntu

# Install Fluent Bit for log processing
echo "Installing Fluent Bit..."
sudo yum install -y fluent-bit

# Configure Fluent Bit
sudo cp /shared/config/fluent-bit.conf /etc/fluent-bit/fluent-bit.conf
sudo systemctl enable fluent-bit
sudo systemctl start fluent-bit

echo "Setup complete!"
```

### Method 2: Custom AMI (Recommended for Production)

**Pros**:
- ✅ Faster node boot
- ✅ No network dependency
- ✅ Pre-cached containers
- ✅ Consistent environment

**Cons**:
- ⚠️ One-time AMI creation effort
- ⚠️ Need to update AMI for changes

**Create Custom AMI**:

```bash
# 1. Find base ParallelCluster AMI
pcluster list-official-images --region us-east-1 --os alinux2

# Output:
# ami-xxxxx: aws-parallelcluster-3.14.0-amzn2-hvm-x86_64-...

# 2. Launch instance from base AMI
aws ec2 run-instances \
    --image-id ami-xxxxx \
    --instance-type c5.xlarge \
    --key-name my-key \
    --subnet-id subnet-xxxxx

# 3. SSH into instance
ssh -i my-key.pem ec2-user@<instance-ip>

# 4. Install Singularity
sudo yum install -y epel-release
sudo yum install -y singularity-ce

# 5. Install additional tools
sudo yum install -y python3 python3-pip fluent-bit

# 6. Pre-pull containers
mkdir -p /opt/containers
cd /opt/containers
singularity pull openroad.sif docker://openroad/flow-ubuntu

# 7. Install Python packages
sudo pip3 install psutil numpy pandas

# 8. Copy SPANK plugin
sudo mkdir -p /opt/spank
# (Copy spank_monitor.so here)

# 9. Clean up
sudo yum clean all
sudo rm -rf /tmp/*

# 10. Create AMI
# From your local machine:
aws ec2 create-image \
    --instance-id i-xxxxx \
    --name "parallelcluster-3.14.0-openroad-singularity" \
    --description "ParallelCluster with Singularity, OpenROAD, SPANK plugin"

# 11. Wait for AMI to be available
aws ec2 describe-images --image-ids ami-yyyyy

# 12. Terminate instance
aws ec2 terminate-instances --instance-ids i-xxxxx
```

**Use Custom AMI**:
```yaml
# cluster-config.yaml
slurm:
  ParallelClusterConfig:
    ComputeNodeAmi: ami-yyyyy  # Your custom AMI
```

---

## Converting Docker Images to Singularity

### On Head Node (One-Time Setup)

```bash
# Pull Docker image and convert to Singularity
singularity pull openroad.sif docker://openroad/flow-ubuntu

# Store in shared location
mv openroad.sif /shared/containers/

# Now all compute nodes can access it
```

### In SLURM Job Script

```bash
#!/bin/bash
#SBATCH --job-name=openroad-test
#SBATCH --nodes=1
#SBATCH --cpus-per-task=16
#SBATCH --mem=32G
#SBATCH --time=02:00:00

# Use Singularity container
singularity exec /shared/containers/openroad.sif \
    openroad /shared/designs/my_design.tcl
```

---

## SPANK Plugin Integration with Singularity

### The Challenge

SPANK plugin needs to monitor processes **inside** the container.

### Solution 1: Monitor from Outside (Recommended)

**How it works**: SPANK plugin monitors the Singularity process (which includes container)

```c
// In SPANK plugin
int slurm_spank_task_post_fork(spank_t sp, int ac, char **av) {
    pid_t job_pid = getpid();
    
    // Monitor this PID - it's the Singularity process
    // Singularity doesn't isolate resources, so this works
    monitor_pid(job_pid);
    
    return SLURM_SUCCESS;
}
```

**Why this works**:
- Singularity doesn't use namespaces by default
- Container processes visible in host `/proc`
- Resource usage (CPU, memory, I/O) tracked correctly

**Verification**:
```bash
# Start Singularity container
singularity exec openroad.sif sleep 1000 &

# Check process tree
ps aux | grep sleep
# Shows: singularity exec ... AND sleep process

# Check /proc
ls /proc/$(pgrep sleep)/
# Accessible from host!
```

### Solution 2: Bind Mount SPANK Plugin (Advanced)

**How it works**: Run SPANK plugin **inside** container

```bash
# Bind mount SPANK plugin into container
singularity exec \
    --bind /opt/spank:/opt/spank \
    --bind /shared:/shared \
    openroad.sif \
    openroad script.tcl
```

**Not recommended** - adds complexity without benefit

---

## File System Access

### Docker Approach (Complicated)

```bash
# Must explicitly mount every path
docker run \
    -v /home/user:/home/user \
    -v /shared:/shared \
    -v /data:/data \
    openroad/flow-ubuntu \
    openroad /home/user/design.tcl
```

### Singularity Approach (Automatic)

```bash
# Automatically mounts: $HOME, /tmp, /shared, /data
singularity exec openroad.sif openroad ~/design.tcl

# Just works! No mount flags needed
```

**What Singularity auto-mounts**:
- `$HOME` - User home directory
- `/tmp` - Temporary files
- `/proc` - Process information
- `/sys` - System information
- `/dev` - Devices
- Current working directory
- Any path specified in `SINGULARITY_BIND`

**For our project**:
```bash
# Design files in /shared/designs
# PDKs in /shared/pdks
# Logs in /shared/logs
# All automatically accessible!

singularity exec /shared/containers/openroad.sif \
    openroad /shared/designs/my_design.tcl
# Output goes to /shared/logs/ - no mount needed!
```

---

## Performance Comparison

### Docker on SLURM

```
Overhead:
- Docker daemon: 50-100MB RAM per node
- Container runtime: 2-5% CPU overhead
- Volume mounts: I/O overhead
- Network bridge: latency

Total: 3-7% overhead
```

### Singularity on SLURM

```
Overhead:
- No daemon: 0MB RAM
- Container runtime: <1% CPU overhead
- Direct filesystem: No I/O overhead
- Host network: No latency

Total: <1% overhead
```

**For our OpenROAD workloads**:
- 2-hour job on c5.4xlarge ($0.68/hour)
- Docker: 2.1 hours × $0.68 = $1.43
- Singularity: 2.02 hours × $0.68 = $1.37
- **Savings**: $0.06 per job (4%)

With 100 jobs/day: **$6/day = $180/month saved**

---

## Resource Tracking Accuracy

### Docker Issues

```bash
# SLURM sees Docker daemon process
# Container processes hidden in namespace
# Resource accounting inaccurate

sbatch --wrap="docker run openroad/flow-ubuntu openroad script.tcl"

# SLURM tracks: docker run process (minimal resources)
# Actual work: Inside container (not tracked properly)
# Result: Inaccurate accounting
```

### Singularity Accuracy

```bash
# SLURM sees Singularity + container processes
# No namespace isolation (by default)
# Resource accounting accurate

sbatch --wrap="singularity exec openroad.sif openroad script.tcl"

# SLURM tracks: All processes correctly
# Result: Accurate accounting
```

**Why this matters for our ML model**:
- We need accurate CPU/memory/IO metrics
- SPANK plugin relies on accurate process tracking
- Inaccurate data = bad predictions

---

## Security Considerations

### Docker Security Issues

```bash
# User in docker group = root equivalent
sudo usermod -aG docker alice

# Alice can now:
docker run -v /:/host ubuntu bash
# Mount entire host filesystem
# Escalate to root
# Security breach!
```

### Singularity Security

```bash
# No special group needed
# User inside = user outside
singularity exec openroad.sif whoami
# Output: alice (not root)

# Cannot escalate privileges
singularity exec openroad.sif sudo bash
# Error: sudo not available

# Cannot access other users' files
singularity exec openroad.sif cat /home/bob/secret.txt
# Error: Permission denied
```

**For multi-user clusters**: Singularity is the only secure option

---

## Recommended Configuration

### Phase 1: Testing (CustomActions)

```yaml
Region: us-east-1
Image:
  Os: alinux2

HeadNode:
  InstanceType: c5.xlarge
  CustomActions:
    OnNodeConfigured:
      Script: s3://bucket/scripts/setup-head-singularity.sh

Scheduling:
  Scheduler: slurm
  SlurmQueues:
    - Name: compute
      ComputeResources:
        - Name: openroad
          InstanceType: c5.4xlarge
          MinCount: 0
          MaxCount: 4
      CustomActions:
        OnNodeConfigured:
          Script: s3://bucket/scripts/setup-compute-singularity.sh
  SlurmSettings:
    EnableMemoryBasedScheduling: true

SharedStorage:
  - MountDir: /shared
    Name: shared-efs
    StorageType: Efs
```

**setup-compute-singularity.sh**:
```bash
#!/bin/bash
set -e

# Install Singularity
sudo yum install -y epel-release
sudo yum install -y singularity-ce

# Install Fluent Bit
sudo yum install -y fluent-bit
sudo cp /shared/config/fluent-bit.conf /etc/fluent-bit/
sudo systemctl enable fluent-bit
sudo systemctl start fluent-bit

# Copy SPANK plugin
sudo cp /shared/spank/spank_monitor.so /usr/lib64/slurm/

# Configure SPANK
echo "required /usr/lib64/slurm/spank_monitor.so" | \
    sudo tee /opt/slurm/etc/plugstack.conf

# Restart slurmd
sudo systemctl restart slurmd

echo "Singularity setup complete!"
```

### Phase 2: Production (Custom AMI)

```yaml
Region: us-east-1
Image:
  Os: alinux2

slurm:
  ParallelClusterConfig:
    ComputeNodeAmi: ami-xxxxx  # Custom AMI with Singularity

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
          MaxCount: 10
  SlurmSettings:
    EnableMemoryBasedScheduling: true
    ScaledownIdletime: 10

SharedStorage:
  - MountDir: /shared
    Name: shared-efs
    StorageType: Efs
```

---

## Job Submission Examples

### Basic Singularity Job

```bash
#!/bin/bash
#SBATCH --job-name=openroad-test
#SBATCH --nodes=1
#SBATCH --cpus-per-task=16
#SBATCH --mem=32G
#SBATCH --time=02:00:00
#SBATCH --output=/shared/logs/job_%j.out

# Set design parameters (for SPANK plugin)
export DESIGN_CELL_COUNT=500000
export DESIGN_FREQ_MHZ=500
export DESIGN_UTILIZATION=0.70

# Run OpenROAD in Singularity
singularity exec /shared/containers/openroad.sif \
    openroad /shared/designs/my_design.tcl
```

### With Our Job Optimizer

```python
# scripts/submit_optimized_job.py
import requests

# Get predictions
response = requests.post('http://localhost:8000/predict', json={
    'cell_count': 500000,
    'net_count': 450000,
    'clock_freq_mhz': 500,
    'utilization_target': 0.70
})

predictions = response.json()

# Calculate resources
max_memory = max(p['memory_gb'] for p in predictions)
total_duration = sum(p['duration_sec'] for p in predictions)

# Create job script
job_script = f"""#!/bin/bash
#SBATCH --job-name=openroad-optimized
#SBATCH --cpus-per-task=16
#SBATCH --mem={int(max_memory * 1.1)}G
#SBATCH --time={int(total_duration * 1.2 / 60)}

singularity exec /shared/containers/openroad.sif \\
    openroad /shared/designs/my_design.tcl
"""

# Submit job
subprocess.run(['sbatch'], input=job_script.encode())
```

---

## Troubleshooting

### Issue 1: Singularity Not Found

```bash
# Error: singularity: command not found

# Solution: Install Singularity
sudo yum install -y epel-release
sudo yum install -y singularity-ce
```

### Issue 2: Container Image Not Found

```bash
# Error: FATAL: container not found: openroad.sif

# Solution: Pull image
singularity pull openroad.sif docker://openroad/flow-ubuntu

# Or use full path
singularity exec /shared/containers/openroad.sif ...
```

### Issue 3: Permission Denied

```bash
# Error: FATAL: could not open image openroad.sif: permission denied

# Solution: Check file permissions
ls -l openroad.sif
chmod 644 openroad.sif  # Make readable
```

### Issue 4: SPANK Plugin Not Monitoring

```bash
# Check if SPANK plugin loaded
scontrol show config | grep -i spank

# Check plugin output
ls /shared/metrics/job_*.json

# Check slurmd logs
sudo journalctl -u slurmd -f
```

---

## Summary

### Key Takeaways

1. ✅ **Use Singularity on SLURM** - Better than Docker in every way for HPC
2. ✅ **Standard AMIs work fine** - Install Singularity via CustomActions
3. ✅ **Custom AMI for production** - Faster boot, pre-cached containers
4. ✅ **SPANK plugin works seamlessly** - No special configuration needed
5. ✅ **File access is automatic** - No volume mounts required
6. ✅ **Security is better** - No privilege escalation risk
7. ✅ **Performance is better** - <1% overhead vs 3-7% for Docker

### Our Deployment Strategy

| Phase | Container | AMI | Reason |
|-------|-----------|-----|--------|
| **Local Dev** | Docker | N/A | Easy setup, good for testing |
| **AWS Testing** | Singularity | Standard + CustomActions | Quick deployment, flexible |
| **AWS Production** | Singularity | Custom AMI | Fast boot, consistent, optimized |

### Cost Impact

**CustomActions approach**: +2-3 minutes per node boot
- 10 nodes × 20 boots/day × 3 min = 600 min = 10 hours
- 10 hours × $0.68 = **$6.80/day wasted** = $204/month

**Custom AMI approach**: Instant boot
- **$204/month saved**
- One-time effort: 1-2 hours to create AMI

**Recommendation**: Start with CustomActions, create custom AMI after testing

---

## References

- [Singularity Documentation](https://sylabs.io/docs/)
- [Apptainer (Singularity fork)](https://apptainer.org/)
- [ParallelCluster Custom AMIs](https://docs.aws.amazon.com/parallelcluster/latest/ug/custom-ami-v3.html)
- [SLURM Container Guide](https://slurm.schedmd.com/containers.html)
- [Our Docker vs Singularity Comparison](DOCKER_VS_SINGULARITY.md)
