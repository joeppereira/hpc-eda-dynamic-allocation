# Deploying Our Workloads with Singularity Containers

## Quick Answer

**YES - We can and SHOULD deploy our workloads in Singularity containers!**

This is actually the **best practice** for HPC/SLURM environments.

---

## Our Complete Stack in Singularity

### What Goes in Containers

```
┌─────────────────────────────────────────────────────┐
│         Singularity Container: OpenROAD             │
│  ┌───────────────────────────────────────────────┐ │
│  │  - OpenROAD binary                            │ │
│  │  - Yosys (synthesis)                          │ │
│  │  - KLayout (viewer)                           │ │
│  │  - Python 3.x                                 │ │
│  │  - TCL libraries                              │ │
│  │  - PDKs (Process Design Kits)                 │ │
│  └───────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────┐
│    Singularity Container: Monitoring & ML           │
│  ┌───────────────────────────────────────────────┐ │
│  │  - Python 3.x                                 │ │
│  │  - psutil (resource monitoring)               │ │
│  │  - pandas, numpy (data processing)            │ │
│  │  - scikit-learn (ML models)                   │ │
│  │  - FastAPI (prediction API)                   │ │
│  │  - PostgreSQL client                          │ │
│  └───────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────┘
```

### What Stays on Host

```
Host System (Compute Nodes)
├── SLURM daemon (slurmd)
├── SPANK plugin (spank_monitor.so)
├── Fluent Bit (log processing)
├── Singularity runtime
└── Shared filesystem mounts (/shared)
```

---

## Architecture with Singularity

### Complete System Flow

```
┌─────────────────────────────────────────────────────────────┐
│                    AWS Parallel Cluster                      │
│                                                              │
│  ┌────────────────────────────────────────────────────────┐ │
│  │                    Head Node                           │ │
│  │  ┌──────────────────────────────────────────────────┐ │ │
│  │  │  Prediction API (Singularity Container)          │ │ │
│  │  │  - FastAPI service                               │ │ │
│  │  │  - ML models                                     │ │ │
│  │  │  - PostgreSQL client                             │ │ │
│  │  └──────────────────────────────────────────────────┘ │ │
│  │  ┌──────────────────────────────────────────────────┐ │ │
│  │  │  Job Optimizer (Python on host)                  │ │ │
│  │  │  - Intercepts job submissions                    │ │ │
│  │  │  - Queries prediction API                        │ │ │
│  │  └──────────────────────────────────────────────────┘ │ │
│  └────────────────────────────────────────────────────────┘ │
│                                                              │
│  ┌────────────────────────────────────────────────────────┐ │
│  │                  Compute Nodes                         │ │
│  │  ┌──────────────────────────────────────────────────┐ │ │
│  │  │  SLURM + SPANK Plugin (Host)                     │ │ │
│  │  │  - Monitors job lifecycle                        │ │ │
│  │  │  - Tracks resources                              │ │ │
│  │  └──────────────────────────────────────────────────┘ │ │
│  │  ┌──────────────────────────────────────────────────┐ │ │
│  │  │  Fluent Bit (Host)                               │ │ │
│  │  │  - Parses OpenROAD logs                          │ │ │
│  │  │  - Detects stage transitions                     │ │ │
│  │  └──────────────────────────────────────────────────┘ │ │
│  │  ┌──────────────────────────────────────────────────┐ │ │
│  │  │  OpenROAD (Singularity Container)                │ │ │
│  │  │  - Runs EDA workload                             │ │ │
│  │  │  - Writes logs to /shared                        │ │ │
│  │  └──────────────────────────────────────────────────┘ │ │
│  └────────────────────────────────────────────────────────┘ │
│                                                              │
│  ┌────────────────────────────────────────────────────────┐ │
│  │              Shared Storage (EFS)                      │ │
│  │  /shared/                                              │ │
│  │  ├── containers/                                       │ │
│  │  │   ├── openroad.sif                                 │ │
│  │  │   └── ml-tools.sif                                 │ │
│  │  ├── designs/                                          │ │
│  │  ├── logs/                                             │ │
│  │  ├── metrics/                                          │ │
│  │  └── spank/                                            │ │
│  └────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
                  ┌───────────────────────┐
                  │  RDS PostgreSQL       │
                  │  - Job metrics        │
                  │  - Design features    │
                  │  - Predictions        │
                  └───────────────────────┘
```

---

## Container Definitions

### Container 1: OpenROAD Workload

**Use existing Docker image**:
```bash
# Convert Docker image to Singularity
singularity pull openroad.sif docker://openroad/flow-ubuntu:latest
```

**Or build custom Singularity image**:

**openroad.def**:
```singularity
Bootstrap: docker
From: ubuntu:22.04

%post
    # Install dependencies
    apt-get update
    apt-get install -y \
        git build-essential cmake \
        python3 python3-pip \
        tcl tcl-dev \
        libboost-all-dev

    # Clone and build OpenROAD
    cd /opt
    git clone --recursive https://github.com/The-OpenROAD-Project/OpenROAD.git
    cd OpenROAD
    mkdir build && cd build
    cmake ..
    make -j$(nproc)
    make install

    # Install Python packages
    pip3 install numpy pandas matplotlib

%environment
    export PATH=/opt/OpenROAD/build/src:$PATH
    export OPENROAD_HOME=/opt/OpenROAD

%runscript
    exec openroad "$@"

%labels
    Author HPC-Optimization-Team
    Version 1.0
```

**Build**:
```bash
sudo singularity build openroad.sif openroad.def
```

### Container 2: ML Tools & Monitoring

**ml-tools.def**:
```singularity
Bootstrap: docker
From: python:3.11-slim

%post
    # Install system dependencies
    apt-get update
    apt-get install -y \
        gcc g++ \
        libpq-dev \
        postgresql-client

    # Install Python packages
    pip3 install --no-cache-dir \
        numpy==1.24.3 \
        pandas==2.0.3 \
        scikit-learn==1.3.0 \
        psutil==5.9.5 \
        sqlalchemy==2.0.19 \
        psycopg2-binary==2.9.7 \
        fastapi==0.103.1 \
        uvicorn==0.23.2 \
        pydantic==2.3.0 \
        matplotlib==3.7.2 \
        seaborn==0.12.2 \
        pyyaml==6.0.1 \
        python-dotenv==1.0.0

%environment
    export PYTHONPATH=/opt/hpc-optimization:$PYTHONPATH

%runscript
    exec python3 "$@"

%labels
    Author HPC-Optimization-Team
    Version 1.0
```

**Build**:
```bash
sudo singularity build ml-tools.sif ml-tools.def
```

---

## Deployment Steps

### Step 1: Build Containers (One-Time, Local)

```bash
# On your laptop or build server

# Option A: Convert existing Docker images
singularity pull openroad.sif docker://openroad/flow-ubuntu:latest

# Option B: Build custom images
sudo singularity build openroad.sif openroad.def
sudo singularity build ml-tools.sif ml-tools.def

# Upload to S3
aws s3 cp openroad.sif s3://my-bucket/containers/
aws s3 cp ml-tools.sif s3://my-bucket/containers/
```

### Step 2: Deploy to Cluster

**setup-head-node.sh**:
```bash
#!/bin/bash
set -e

echo "Setting up head node..."

# Install Singularity
sudo yum install -y epel-release
sudo yum install -y singularity-ce

# Download containers from S3
mkdir -p /shared/containers
aws s3 cp s3://my-bucket/containers/openroad.sif /shared/containers/
aws s3 cp s3://my-bucket/containers/ml-tools.sif /shared/containers/

# Copy project files
aws s3 cp s3://my-bucket/hpc-optimization.tar.gz /shared/
cd /shared
tar -xzf hpc-optimization.tar.gz

# Start prediction API in container
cat > /etc/systemd/system/prediction-api.service <<EOF
[Unit]
Description=HPC Resource Prediction API
After=network.target

[Service]
Type=simple
User=ec2-user
WorkingDirectory=/shared/hpc-optimization
ExecStart=/usr/bin/singularity exec \\
    --bind /shared:/shared \\
    /shared/containers/ml-tools.sif \\
    uvicorn prediction.api:app --host 0.0.0.0 --port 8000
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable prediction-api
sudo systemctl start prediction-api

echo "Head node setup complete!"
```

**setup-compute-node.sh**:
```bash
#!/bin/bash
set -e

echo "Setting up compute node..."

# Install Singularity
sudo yum install -y epel-release
sudo yum install -y singularity-ce

# Install Fluent Bit
sudo yum install -y fluent-bit

# Configure Fluent Bit
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

echo "Compute node setup complete!"
```

### Step 3: Cluster Configuration

**cluster-config.yaml**:
```yaml
Region: us-east-1
Image:
  Os: alinux2

HeadNode:
  InstanceType: c5.xlarge
  CustomActions:
    OnNodeConfigured:
      Script: s3://my-bucket/scripts/setup-head-node.sh

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
          Script: s3://my-bucket/scripts/setup-compute-node.sh
  SlurmSettings:
    ScaledownIdletime: 10
    EnableMemoryBasedScheduling: true

SharedStorage:
  - MountDir: /shared
    Name: shared-efs
    StorageType: Efs
```

---

## Job Submission with Singularity

### Basic Job Script

**openroad_job.sh**:
```bash
#!/bin/bash
#SBATCH --job-name=openroad-placement
#SBATCH --nodes=1
#SBATCH --cpus-per-task=16
#SBATCH --mem=32G
#SBATCH --time=02:00:00
#SBATCH --output=/shared/logs/job_%j.out

# Set design parameters (for SPANK plugin)
export DESIGN_CELL_COUNT=500000
export DESIGN_NET_COUNT=450000
export DESIGN_FREQ_MHZ=500
export DESIGN_UTILIZATION=0.70

# Run OpenROAD in Singularity container
singularity exec \
    --bind /shared:/shared \
    /shared/containers/openroad.sif \
    openroad /shared/designs/my_design.tcl

echo "Job completed!"
```

**Submit**:
```bash
sbatch openroad_job.sh
```

### Job with ML Prediction

**optimized_job.sh**:
```bash
#!/bin/bash
#SBATCH --job-name=openroad-optimized
#SBATCH --nodes=1
#SBATCH --cpus-per-task=16
#SBATCH --mem=48G  # Predicted by ML model
#SBATCH --time=02:30:00  # Predicted by ML model
#SBATCH --output=/shared/logs/job_%j.out

# Design parameters
export DESIGN_CELL_COUNT=500000
export DESIGN_NET_COUNT=450000
export DESIGN_FREQ_MHZ=500
export DESIGN_UTILIZATION=0.70

# Query prediction API (running in container on head node)
PREDICTIONS=$(curl -s http://head-node:8000/predict \
    -H "Content-Type: application/json" \
    -d '{
        "cell_count": 500000,
        "net_count": 450000,
        "clock_freq_mhz": 500,
        "utilization_target": 0.70
    }')

echo "Predictions: $PREDICTIONS"

# Run OpenROAD
singularity exec \
    --bind /shared:/shared \
    /shared/containers/openroad.sif \
    openroad /shared/designs/my_design.tcl
```

### Automated Job Optimizer

**submit_optimized.py** (runs on head node):
```python
#!/usr/bin/env python3
import sys
import subprocess
import requests
import json

def submit_optimized_job(design_file, design_params):
    """Submit job with ML-predicted resources"""
    
    # Query prediction API (running in Singularity on head node)
    response = requests.post('http://localhost:8000/predict', json=design_params)
    predictions = response.json()
    
    # Calculate resources
    max_memory = max(p['memory_gb'] for p in predictions)
    total_duration = sum(p['duration_sec'] for p in predictions)
    max_cpus = max(p['cpu_cores'] for p in predictions)
    
    # Add 20% buffer
    memory_gb = int(max_memory * 1.2)
    duration_min = int(total_duration * 1.2 / 60)
    
    # Create job script
    job_script = f"""#!/bin/bash
#SBATCH --job-name=openroad-{design_params['cell_count']}
#SBATCH --cpus-per-task={max_cpus}
#SBATCH --mem={memory_gb}G
#SBATCH --time={duration_min:02d}:00
#SBATCH --output=/shared/logs/job_%j.out

# Design parameters
export DESIGN_CELL_COUNT={design_params['cell_count']}
export DESIGN_NET_COUNT={design_params['net_count']}
export DESIGN_FREQ_MHZ={design_params['clock_freq_mhz']}
export DESIGN_UTILIZATION={design_params['utilization_target']}

# Run OpenROAD in Singularity
singularity exec \\
    --bind /shared:/shared \\
    /shared/containers/openroad.sif \\
    openroad {design_file}
"""
    
    # Submit job
    result = subprocess.run(
        ['sbatch'],
        input=job_script.encode(),
        capture_output=True
    )
    
    job_id = result.stdout.decode().split()[-1]
    print(f"Submitted job {job_id} with predicted resources:")
    print(f"  CPUs: {max_cpus}")
    print(f"  Memory: {memory_gb}G")
    print(f"  Time: {duration_min} minutes")
    
    return job_id

if __name__ == '__main__':
    design_params = {
        'cell_count': 500000,
        'net_count': 450000,
        'clock_freq_mhz': 500,
        'utilization_target': 0.70
    }
    
    submit_optimized_job('/shared/designs/my_design.tcl', design_params)
```

---

## SPANK Plugin Integration

### How SPANK Monitors Singularity Jobs

**The Good News**: SPANK plugin works seamlessly with Singularity!

**Why it works**:
```bash
# When you run:
singularity exec openroad.sif openroad script.tcl

# Process tree looks like:
slurmd (SLURM daemon)
  └── slurmstepd (job step daemon)
      └── singularity exec ... (PID 12345)
          └── openroad script.tcl (PID 12346)

# SPANK plugin monitors PID 12345 (singularity process)
# Singularity doesn't isolate resources by default
# So monitoring PID 12345 captures all container activity!
```

**SPANK plugin code** (no changes needed):
```c
int slurm_spank_task_post_fork(spank_t sp, int ac, char **av) {
    pid_t job_pid = getpid();
    
    // This PID includes Singularity + container processes
    // Resource tracking works correctly!
    monitor_pid(job_pid);
    
    return SLURM_SUCCESS;
}
```

**Verification**:
```bash
# Submit job
sbatch openroad_job.sh

# Check process tree
ps auxf | grep singularity

# Check SPANK plugin output
cat /shared/metrics/job_12345.json
# Shows correct CPU, memory, I/O metrics!
```

---

## Data Flow with Singularity

### Complete Pipeline

```
1. User submits job
   ↓
2. Job Optimizer (Python on head node)
   - Queries Prediction API (Singularity container)
   - Modifies job resources
   ↓
3. SLURM schedules job
   ↓
4. Compute node starts job
   - SPANK plugin hooks in (host)
   - Fluent Bit starts monitoring logs (host)
   ↓
5. Singularity container runs OpenROAD
   - Writes logs to /shared/logs/ (auto-mounted)
   - Accesses designs from /shared/designs/ (auto-mounted)
   ↓
6. SPANK plugin monitors resources (host)
   - Tracks CPU, memory, I/O
   - Reads current stage from Fluent Bit output
   - Associates metrics with stage
   ↓
7. Job completes
   - SPANK plugin exports metrics to /shared/metrics/
   ↓
8. Import script (Singularity container)
   - Reads metrics JSON
   - Imports to PostgreSQL
   ↓
9. Model retraining (Singularity container)
   - Queries database
   - Trains new models
   - Updates prediction API
```

---

## Advantages of Singularity for Our Project

### 1. Seamless File Access

**Without Singularity** (Docker):
```bash
# Must mount every path explicitly
docker run \
    -v /shared/designs:/shared/designs \
    -v /shared/logs:/shared/logs \
    -v /shared/pdks:/shared/pdks \
    openroad/flow-ubuntu \
    openroad /shared/designs/my_design.tcl
```

**With Singularity**:
```bash
# Automatic access to /shared
singularity exec openroad.sif openroad /shared/designs/my_design.tcl
# Just works!
```

### 2. SPANK Plugin Compatibility

**Without Singularity** (Docker):
- Container processes hidden in namespace
- SPANK plugin can't see inside container
- Resource tracking inaccurate
- Need complex workarounds

**With Singularity**:
- Container processes visible to host
- SPANK plugin monitors correctly
- Resource tracking accurate
- No workarounds needed

### 3. Security

**Without Singularity** (Docker):
- Users need docker group membership
- docker group = root equivalent
- Security risk on shared cluster

**With Singularity**:
- No special privileges needed
- User inside = user outside
- Secure for multi-user cluster

### 4. Performance

**Without Singularity** (Docker):
- Docker daemon overhead: 50-100MB RAM per node
- Container runtime: 2-5% CPU overhead
- Volume mounts: I/O overhead

**With Singularity**:
- No daemon: 0MB overhead
- Container runtime: <1% CPU overhead
- Direct filesystem: No I/O overhead

---

## Testing Locally with Singularity

### Install Singularity on Mac

```bash
# Install via Homebrew
brew install --cask singularity

# Or use Lima VM
brew install lima
limactl start template://singularity
lima singularity --version
```

### Install Singularity on Linux

```bash
# Ubuntu/Debian
sudo apt-get update
sudo apt-get install -y singularity-ce

# RHEL/CentOS/Amazon Linux
sudo yum install -y epel-release
sudo yum install -y singularity-ce
```

### Test Locally

```bash
# Pull OpenROAD container
singularity pull openroad.sif docker://openroad/flow-ubuntu

# Test run
singularity exec openroad.sif openroad -version

# Run with our monitoring
singularity exec openroad.sif python3 monitoring/resource_monitor.py \
    --command "openroad /path/to/design.tcl" \
    --output metrics.json
```

---

## Migration Path

### Phase 1: Local Development (Current)

```bash
# Use Docker locally
docker run openroad/flow-ubuntu openroad script.tcl
```

### Phase 2: Convert to Singularity (Testing)

```bash
# Convert Docker images
singularity pull openroad.sif docker://openroad/flow-ubuntu
singularity pull ml-tools.sif docker://python:3.11-slim

# Test locally
singularity exec openroad.sif openroad script.tcl
```

### Phase 3: Deploy to AWS (Production)

```bash
# Upload containers to S3
aws s3 cp openroad.sif s3://bucket/containers/
aws s3 cp ml-tools.sif s3://bucket/containers/

# Deploy cluster with CustomActions
pcluster create-cluster --cluster-name hpc-optimization \
    --cluster-configuration cluster-config.yaml

# Submit jobs
sbatch openroad_job.sh
```

---

## Summary

### Can We Deploy Our Workloads in Singularity?

**YES - Absolutely!** And we **should** for production.

### What Changes?

| Component | Current (Local) | Production (Singularity) |
|-----------|----------------|--------------------------|
| **OpenROAD** | Docker container | Singularity container |
| **ML Tools** | Python on host | Singularity container |
| **SPANK Plugin** | N/A (local testing) | Host (works with Singularity) |
| **Fluent Bit** | N/A (local testing) | Host (monitors container logs) |
| **Job Submission** | `docker run ...` | `sbatch` + `singularity exec ...` |

### Benefits

1. ✅ **Better SLURM integration** - Native support
2. ✅ **Accurate resource tracking** - SPANK plugin works perfectly
3. ✅ **Simpler file access** - Automatic /shared mounting
4. ✅ **Better security** - No privilege escalation
5. ✅ **Better performance** - <1% overhead
6. ✅ **Production ready** - Industry standard for HPC

### Effort Required

**Minimal**:
1. Convert Docker images: `singularity pull openroad.sif docker://openroad/flow-ubuntu`
2. Update job scripts: Change `docker run` to `singularity exec`
3. Deploy via CustomActions: Install Singularity on compute nodes

**Total time**: 2-4 hours for complete migration

### Recommendation

**Do it!** Singularity is the right choice for production HPC workloads.
