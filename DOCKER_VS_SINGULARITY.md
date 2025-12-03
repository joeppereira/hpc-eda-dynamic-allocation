# Docker vs Singularity for HPC/EDA Workloads

## Quick Comparison

| Feature | Docker | Singularity/Apptainer | Winner for HPC |
|---------|--------|----------------------|----------------|
| **Root Privileges** | Required | Not required | ✅ Singularity |
| **User Mapping** | Root inside container | Same user inside/outside | ✅ Singularity |
| **File System Access** | Isolated, needs volumes | Direct access to host | ✅ Singularity |
| **MPI Support** | Complex | Native | ✅ Singularity |
| **GPU Access** | Needs --gpus flag | Native with --nv | ✅ Singularity |
| **Security** | Daemon runs as root | No daemon, user-level | ✅ Singularity |
| **HPC Scheduler Integration** | Difficult | Native (SLURM, PBS) | ✅ Singularity |
| **Performance** | Good | Excellent (near-native) | ✅ Singularity |
| **Ease of Use** | Very easy | Easy | ✅ Docker |
| **Ecosystem** | Huge (Docker Hub) | Growing | ✅ Docker |
| **Local Development** | Excellent | Good | ✅ Docker |

## Detailed Analysis

### 1. Privilege Model

**Docker:**
```bash
# Requires root/sudo or docker group membership
docker run ubuntu
# Inside container: you are root by default
# Security concern: root in container = potential root on host
```

**Singularity:**
```bash
# No root required
singularity run ubuntu.sif
# Inside container: you are the same user as outside
# Security: cannot escalate privileges
```

**Why it matters for HPC:**
- HPC users don't have root access
- Shared clusters need security
- ✅ **Singularity wins** - designed for multi-user HPC

### 2. File System Access

**Docker:**
```bash
# Must explicitly mount volumes
docker run -v /data:/data -v /home/user:/home/user myimage
# Home directory not accessible by default
# Complicated path mapping
```

**Singularity:**
```bash
# Automatically mounts: $HOME, /tmp, /proc, /sys, /dev
singularity run myimage.sif
# Can access all your files immediately
# No path mapping needed
```

**Why it matters for EDA:**
- Design files in home directory
- PDKs in shared locations
- Libraries in system paths
- ✅ **Singularity wins** - seamless file access

### 3. MPI and Parallel Computing

**Docker:**
```bash
# MPI across containers is complex
# Requires network configuration
# Performance overhead
# Not well integrated with HPC schedulers
```

**Singularity:**
```bash
# Native MPI support
singularity exec myimage.sif mpirun -np 16 myapp
# Uses host MPI for communication
# Works with SLURM, PBS, LSF
# Near-native performance
```

**Why it matters for HPC:**
- OpenROAD can use MPI for parallel routing
- GROMACS uses MPI extensively
- ✅ **Singularity wins** - built for HPC

### 4. GPU Access

**Docker:**
```bash
# Requires nvidia-docker or --gpus flag
docker run --gpus all nvidia/cuda:11.0
# Extra setup needed
```

**Singularity:**
```bash
# Simple --nv flag
singularity run --nv myimage.sif
# Automatically binds NVIDIA libraries
```

**Why it matters:**
- Some EDA tools use GPU acceleration
- ML models may need GPU
- ✅ **Singularity wins** - simpler GPU access

### 5. SLURM Integration

**Docker:**
```bash
# Not designed for SLURM
# Requires custom scripts
# Job accounting difficult
# Resource limits tricky
```

**Singularity:**
```bash
# Native SLURM integration
sbatch --wrap="singularity exec myimage.sif openroad script.tcl"
# SLURM tracks resources correctly
# Works with SPANK plugins
# Job accounting works
```

**Why it matters for our project:**
- We're using SLURM for scheduling
- Need SPANK plugin integration
- Need accurate resource tracking
- ✅ **Singularity wins** - designed for HPC schedulers

### 6. Performance

**Docker:**
- Overhead: 2-5% for CPU
- Storage: overlay filesystem can be slow
- Network: bridge mode has overhead

**Singularity:**
- Overhead: <1% (near-native)
- Storage: direct host filesystem access
- Network: uses host network by default

**Why it matters:**
- EDA workloads are compute-intensive
- Every % matters for large jobs
- ✅ **Singularity wins** - better performance

### 7. Security in Multi-User Environment

**Docker:**
- Daemon runs as root
- Users in docker group = root equivalent
- Container escape = root on host
- Not suitable for shared HPC clusters

**Singularity:**
- No daemon
- User inside = user outside
- Cannot escalate privileges
- Designed for shared clusters

**Why it matters:**
- HPC clusters are multi-user
- Security is critical
- ✅ **Singularity wins** - secure by design

## Use Cases

### Use Docker When:
- ✅ Local development on your laptop
- ✅ CI/CD pipelines
- ✅ Microservices architecture
- ✅ Web applications
- ✅ You have root access
- ✅ Single-user environment

### Use Singularity When:
- ✅ HPC clusters (SLURM, PBS, LSF)
- ✅ Multi-user shared systems
- ✅ MPI/parallel applications
- ✅ GPU computing on HPC
- ✅ No root access
- ✅ Need native performance
- ✅ EDA/scientific workloads

## For Our Project

### Current Situation:
- Local development (Docker available)
- Will deploy to AWS Parallel Cluster (SLURM)
- Need SPANK plugin integration
- Need accurate resource tracking

### Recommendation:

**Phase 1 (Local Testing): Docker**
```bash
# Easy to use locally
docker pull openroad/flow-ubuntu
docker run -v $(pwd):/work openroad/flow-ubuntu openroad -version
```

**Phase 2 (Production Cluster): Singularity**
```bash
# On AWS Parallel Cluster
singularity pull docker://openroad/flow-ubuntu
sbatch --wrap="singularity exec openroad.sif openroad script.tcl"
# Works with SLURM + SPANK plugin
```

### Why Both?
- **Docker locally**: Easier setup, good for development
- **Singularity on cluster**: Better HPC integration, required for SLURM
- **Compatibility**: Can convert Docker images to Singularity:
  ```bash
  singularity build openroad.sif docker://openroad/flow-ubuntu
  ```

## Conversion Between Formats

```bash
# Docker image → Singularity
singularity build myimage.sif docker://username/myimage:tag

# Docker Hub → Singularity
singularity build openroad.sif docker://openroad/flow-ubuntu

# Local Docker → Singularity
singularity build myimage.sif docker-daemon://myimage:tag
```

## Summary for HPC Resource Optimization Project

| Requirement | Docker | Singularity | Our Choice |
|-------------|--------|-------------|------------|
| Local testing | ✅ Excellent | ⚠️ Good | Docker |
| SLURM integration | ❌ Poor | ✅ Excellent | Singularity |
| SPANK plugin | ❌ Difficult | ✅ Native | Singularity |
| Resource tracking | ⚠️ Complex | ✅ Native | Singularity |
| File access | ⚠️ Needs mounts | ✅ Automatic | Singularity |
| Multi-user | ❌ Security risk | ✅ Secure | Singularity |
| Performance | ⚠️ Good | ✅ Excellent | Singularity |

**Verdict**: 
- Use **Docker** for local development and testing
- Use **Singularity** for production on AWS Parallel Cluster
- Convert Docker images to Singularity for deployment
