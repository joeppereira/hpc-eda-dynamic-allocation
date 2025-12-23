# ML-Driven HPC Resource Optimization Architecture

## AWS Architecture Diagram (Compact)

**Figure 1: ML-Driven HPC Resource Optimization System Architecture**

This diagram illustrates a complete machine learning-driven resource optimization system deployed on AWS. The architecture shows how jobs flow from user submission through intelligent prediction to optimized execution. At the top, a Head Node contains the SLURM scheduler, a job submission plugin that intercepts requests, and a prediction API powered by machine learning models. These components work together to predict optimal CPU, memory, and instance type requirements before jobs run. Below the Head Node, auto-scaling compute nodes execute the actual workloads while monitoring resource usage in real-time. Shared storage (choose from EFS, FSx for Lustre, or FSx for NetApp ONTAP based on performance and feature requirements) provides high-performance access to design files and results across all nodes. Supporting AWS services including S3, RDS, CloudWatch, and IAM handle backups, database scaling, monitoring, and security. The key takeaway: this closed-loop system continuously learns from actual job execution to improve future predictions, eliminating out-of-memory failures and recovering wasted compute capacity by matching workloads to the right resources.

```
┌──────────────────────────────────────────────────────────────────────────────────┐
│                          AWS Region (us-east-1) - VPC                             │
│                                                                                    │
│  ┌──────────────────────────────────────────────────────────────────────────┐   │
│  │  Head Node (EC2)                                                          │   │
│  │  ┌────────────┐  ┌────────────┐  ┌────────────┐  ┌────────────┐         │   │
│  │  │   SLURM    │◄─│Job Submit  │◄─│Prediction  │  │ Dashboard  │         │   │
│  │  │ Controller │  │Plugin (Lua)│  │API (ML)    │  │  (Web UI)  │         │   │
│  │  └──────┬─────┘  └────────────┘  └─────┬──────┘  └────────────┘         │   │
│  │         │                                │                                 │   │
│  │         │                                ▼                                 │   │
│  │         │                         ┌────────────┐                          │   │
│  │         │                         │ Metrics DB │                          │   │
│  │         │                         │(SQLite/RDS)│                          │   │
│  │         │                         └────────────┘                          │   │
│  └─────────┼──────────────────────────────────────────────────────────────┘   │
│            │                                                                    │
│            ▼                                                                    │
│  ┌──────────────────────────────────────────────────────────────────────────┐   │
│  │  Compute Nodes (Auto Scaling)                                            │   │
│  │  ┌──────────┐  ┌──────────┐  ┌──────────┐                               │   │
│  │  │Compute-1 │  │Compute-2 │  │Compute-N │  ...                          │   │
│  │  │ slurmd   │  │ slurmd   │  │ slurmd   │                               │   │
│  │  │ Monitor  │  │ Monitor  │  │ Monitor  │                               │   │
│  │  │ Workload │  │ Workload │  │ Workload │                               │   │
│  │  │(c8,r8,m8)│  │(c8,r8,m8)│  │(c8,r8,m8)│                               │   │
│  │  └──────────┘  └──────────┘  └──────────┘                               │   │
│  └──────────────────────────────────────────────────────────────────────────┘   │
│                                                                                    │
│  ┌──────────────────────────────────────────────────────────────────────────┐   │
│  │  Shared Storage: EFS / FSx Lustre / FSx ONTAP (choose one)               │   │
│  └──────────────────────────────────────────────────────────────────────────┘   │
│                                                                                    │
│  ┌──────────────────────────────────────────────────────────────────────────┐   │
│  │  AWS Services: S3 (Backups) | RDS (DB) | CloudWatch | IAM               │   │
│  └──────────────────────────────────────────────────────────────────────────┘   │
│                                                                                    │
│  ┌──────────────────────────────────────────────────────────────────────────┐   │
│  │  Users ──SSH/HTTPS──► Head Node (Job submit, Monitoring, Dashboard)      │   │
│  └──────────────────────────────────────────────────────────────────────────┘   │
└──────────────────────────────────────────────────────────────────────────────────┘
```

## Data Flow Diagram

**Figure 3: ML-Driven Resource Optimization Flow (Compact)**

This five-stage closed-loop process enables continuous learning. Jobs are intercepted at submission, predictions query historical data for optimal resources, SLURM allocates based on predictions, monitors track actual usage during execution, and metrics feed back to retrain the ML model—each job benefits from all previous jobs.

```
1. SUBMIT ──► 2. PREDICT ──► 3. ALLOCATE ──► 4. EXECUTE ──► 5. LEARN
   │              │               │               │               │
   User        ML API          SLURM          Monitor        Update DB
   sbatch     (history)      (schedule)      (actual)       (retrain)
   │              │               │               │               │
   └──────────────┴───────────────┴───────────────┴───────────────┘
                       Continuous Improvement Loop
```

**Detailed Flow**:

1. **Job Submission**: User submits with design parameters → Job plugin intercepts
2. **Prediction**: API queries database → ML model predicts CPU/memory/instance → Returns recommendations
3. **Resource Allocation**: SLURM adjusts job resources → Selects optimal instance type → Dispatches to compute node
4. **Job Execution**: Container runs workload → Monitors track CPU/memory/I/O → Job completes
5. **Learning Feedback**: Collect actual metrics → Store in database → Retrain ML model → Improve next predictions

**Key Benefit**: Progressive elimination of resource waste and OOM failures through continuous learning from execution history.

**Note on Dynamic Allocation**: Unlike Ansys tools which support MPI for runtime resource scaling, EDA tools (OpenROAD, Synopsys, Cadence, Mentor) do not support MPI. Therefore, dynamic allocation for EDA workloads occurs at job submission time through SLURM job modifications before deployment, not during runtime. The prediction engine adjusts CPU and memory allocations in the SLURM job script based on design parameters before the job starts executing.

## Component Descriptions

### Head Node / Master Server
- **SLURM Controller (slurmctld)**: Manages job queue, scheduling, and resource allocation
- **Job Submit Plugin**: Intercepts job submissions and queries prediction API
- **Prediction API**: FastAPI service providing ML-based resource predictions
- **Metrics Database**: Stores historical job data for training and predictions
- **Dashboard**: Web-based monitoring and visualization interface

### Compute Nodes
- **SLURM Daemon (slurmd)**: Executes jobs and reports status to controller
- **Resource Monitor**: Tracks real-time CPU, memory, and I/O usage
- **Workload Execution**: Runs EDA/HPC applications in containers or natively
- **Instance Types**: Flexible selection (c8 for compute, r8 for memory, m8 for balanced)

### Shared Storage
- **Amazon EFS / FSx for Lustre / FSx for NetApp ONTAP**: Choose one high-performance shared filesystem based on your requirements
  - **EFS**: General-purpose NFS, good for most workloads
  - **FSx for Lustre**: Optimized for HPC, highest throughput for compute-intensive jobs
  - **FSx for NetApp ONTAP**: Enterprise features, multi-protocol support (NFS/SMB), advanced data management
- **Contents**: Design files, job results, metrics database, ML models
- **Access**: Mounted on all nodes for seamless data sharing

### Supporting Services
- **Amazon S3**: Backup storage for results, logs, and artifacts
- **Amazon RDS**: Production-grade PostgreSQL database (optional, scales beyond SQLite)
- **CloudWatch**: Monitoring, logging, and alerting
- **IAM Roles**: Security and access control

## Key Features

### Instance Affinity Optimization
The system automatically matches workloads to optimal instance types:
- **Memory-intensive** (place & route) → r8 family
- **Compute-intensive** (synthesis) → c8 family
- **Balanced** (verification) → m8 family

### Continuous Learning
- Collects actual resource usage from every job
- Updates ML model with new data
- Improves predictions over time
- Adapts to changing workload patterns

### OOM Prevention
- Predicts memory requirements with safety buffers
- Adjusts allocations before job starts
- Monitors during execution
- Eliminates out-of-memory failures

### Cost Optimization
- Reduces over-allocation waste
- Matches workloads to cost-effective instances
- Tracks savings in real-time dashboard
- Provides ROI metrics

## Deployment Options

This architecture supports multiple deployment configurations:

1. **AWS ParallelCluster + SLURM** (shown above)
2. **AWS PCS (Parallel Computing Service)** - Managed SLURM
3. **AWS PCS with SUSE Linux** - Enterprise Linux support
4. **AWS Batch** - Container-based serverless compute

All configurations maintain the core prediction and optimization capabilities while adapting to the specific infrastructure.

---

**Note**: This architecture diagram represents the AWS ParallelCluster deployment. For AWS PCS or AWS Batch deployments, the compute infrastructure changes but the ML prediction engine, monitoring, and optimization logic remain consistent.


---

## Containerization with Singularity

**Figure 2: Singularity Container Execution Flow (Compact)**

This diagram shows how EDA workloads run in Singularity containers while maintaining seamless integration with SLURM scheduling and resource monitoring. Containers run as the user (not root), automatically mount shared filesystems, and allow SLURM and monitoring tools to track resources accurately.

```
┌─────────────────────────────────────────────────────────────────┐
│  Compute Node: Singularity Container Execution                  │
│                                                                  │
│  Host: slurmd | SPANK Plugin | Fluent Bit                       │
│         │            │              │                            │
│         └────────────┼──────────────┘                            │
│                      ▼                                           │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │ Singularity: singularity exec openroad.sif openroad ...    │ │
│  │                                                             │ │
│  │  ┌───────────────────────────────────────────────────────┐ │ │
│  │  │ Container: OpenROAD EDA Tools                         │ │ │
│  │  │ • Synthesis • Floorplan • Place • Route • Timing     │ │ │
│  │  │                                                        │ │ │
│  │  │ Auto-mounted: /shared/designs, /shared/logs, $HOME   │ │ │
│  │  └───────────────────────────────────────────────────────┘ │ │
│  └────────────────────────────────────────────────────────────┘ │
│                                                                  │
│  Resources tracked: CPU, Memory, I/O (visible to host)          │
└─────────────────────────────────────────────────────────────────┘
```

**Why Singularity**: No root required • Auto-mounts filesystems • Native SLURM integration • Accurate monitoring • <1% overhead

**Build & Submit**:
```
# Build
Bootstrap: docker
From: ubuntu:22.04
%post
    apt-get update && apt-get install -y git cmake
    cd /opt && git clone https://github.com/The-OpenROAD-Project/OpenROAD.git
    cd OpenROAD && mkdir build && cd build && cmake .. && make install

# Submit
#!/bin/bash
#SBATCH --cpus-per-task=16 --mem=32G
export DESIGN_CELL_COUNT=500000
singularity exec /shared/containers/openroad.sif openroad /shared/designs/my_design.tcl
```

**ML-Optimized Job Submission**:
```
import requests, subprocess

# Query prediction API
response = requests.post('http://head-node:8000/predict', json={
    'cell_count': 500000, 'net_count': 450000,
    'clock_freq_mhz': 500, 'utilization_target': 0.70
})
predictions = response.json()

# Calculate resources
max_memory = max(p['memory_gb'] for p in predictions)
total_duration = sum(p['duration_sec'] for p in predictions)

# Submit optimized job
job_script = f"""#!/bin/bash
#SBATCH --cpus-per-task=16 --mem={int(max_memory * 1.2)}G
singularity exec /shared/containers/openroad.sif openroad /shared/designs/my_design.tcl
"""
subprocess.run(['sbatch'], input=job_script.encode())
```

---

## Additional Code Examples

### Log Analysis and Feature Extraction

Parsing EDA tool logs to extract design parameters for prediction:

```python
import re, json

def parse_openroad_log(log_file):
    """Extract design metrics from OpenROAD log files"""
    metrics = {}
    
    with open(log_file, 'r') as f:
        content = f.read()
        
        # Extract cell count
        if match := re.search(r'Number of cells:\s+(\d+)', content):
            metrics['cell_count'] = int(match.group(1))
        
        # Extract net count
        if match := re.search(r'Number of nets:\s+(\d+)', content):
            metrics['net_count'] = int(match.group(1))
        
        # Extract clock frequency
        if match := re.search(r'Clock period:\s+([\d.]+)\s*ns', content):
            period_ns = float(match.group(1))
            metrics['clock_freq_mhz'] = 1000.0 / period_ns
        
        # Extract utilization
        if match := re.search(r'Core utilization:\s+([\d.]+)%', content):
            metrics['utilization_target'] = float(match.group(1)) / 100.0
    
    return metrics

# Usage
design_params = parse_openroad_log('/shared/logs/my_design.log')
print(json.dumps(design_params, indent=2))
```

### Prediction API Inference

Querying the ML prediction engine for resource recommendations:

```python
import requests

def get_resource_prediction(design_params):
    """Query prediction API for optimal resource allocation"""
    
    api_url = 'http://head-node:8000/predict'
    
    # Send design parameters
    response = requests.post(api_url, json=design_params, timeout=5)
    response.raise_for_status()
    
    predictions = response.json()
    
    # Aggregate predictions across all stages
    total_cpu = max(p['cpu_cores'] for p in predictions)
    total_memory = max(p['memory_gb'] for p in predictions)
    total_duration = sum(p['duration_sec'] for p in predictions)
    
    # Determine optimal instance type based on memory/CPU ratio
    mem_per_cpu = total_memory / total_cpu
    if mem_per_cpu > 6:
        instance_type = 'r8'  # Memory-optimized
    elif mem_per_cpu < 2:
        instance_type = 'c8'  # Compute-optimized
    else:
        instance_type = 'm8'  # Balanced
    
    return {
        'cpu_cores': total_cpu,
        'memory_gb': total_memory,
        'duration_sec': total_duration,
        'instance_family': instance_type,
        'stages': predictions
    }

# Usage
design = {'cell_count': 500000, 'net_count': 450000, 
          'clock_freq_mhz': 500, 'utilization_target': 0.70}
recommendation = get_resource_prediction(design)
print(f"Recommended: {recommendation['cpu_cores']} CPUs, "
      f"{recommendation['memory_gb']}GB RAM, "
      f"Instance: {recommendation['instance_family']}")
```

### SLURM Job Submit Plugin (Lua)

Intercepting job submissions and dynamically adjusting resources:

```lua
function slurm_job_submit(job_desc, part_list, submit_uid)
    -- Extract design parameters from environment variables
    local cell_count = job_desc.environment['DESIGN_CELL_COUNT']
    local net_count = job_desc.environment['DESIGN_NET_COUNT']
    local clock_freq = job_desc.environment['DESIGN_FREQ_MHZ']
    
    if cell_count and net_count and clock_freq then
        -- Query prediction API
        local curl_cmd = string.format(
            'curl -s -X POST http://localhost:8000/predict ' ..
            '-H "Content-Type: application/json" ' ..
            '-d \'{"cell_count":%s,"net_count":%s,"clock_freq_mhz":%s}\'',
            cell_count, net_count, clock_freq
        )
        
        local handle = io.popen(curl_cmd)
        local result = handle:read("*a")
        handle:close()
        
        -- Parse JSON response (simplified)
        local cpu = result:match('"cpu_cores":(%d+)')
        local mem = result:match('"memory_gb":(%d+)')
        
        if cpu and mem then
            -- Update job resource requirements
            job_desc.min_cpus = tonumber(cpu)
            job_desc.pn_min_memory = tonumber(mem) * 1024  -- Convert to MB
            
            slurm.log_info("Dynamic allocation: CPU=%s, Memory=%sGB", 
                          cpu, mem)
        end
    end
    
    return slurm.SUCCESS
end

function slurm_job_modify(job_desc, job_rec, part_list, modify_uid)
    return slurm.SUCCESS
end
```

### Feedback Loop: Storing Actual Metrics

Collecting actual resource usage after job completion:

```python
import sqlite3, json
from datetime import datetime

def store_job_metrics(job_id, design_params, actual_usage):
    """Store job execution metrics for model retraining"""
    
    conn = sqlite3.connect('/shared/db/metrics.db')
    cursor = conn.cursor()
    
    cursor.execute('''
        INSERT INTO job_metrics 
        (job_id, timestamp, cell_count, net_count, clock_freq_mhz,
         actual_cpu_cores, actual_memory_gb, actual_duration_sec,
         peak_memory_gb, avg_cpu_utilization)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ''', (
        job_id,
        datetime.now().isoformat(),
        design_params['cell_count'],
        design_params['net_count'],
        design_params['clock_freq_mhz'],
        actual_usage['cpu_cores'],
        actual_usage['memory_gb'],
        actual_usage['duration_sec'],
        actual_usage['peak_memory_gb'],
        actual_usage['avg_cpu_utilization']
    ))
    
    conn.commit()
    conn.close()
    
    print(f"Stored metrics for job {job_id}")

# Usage - called after job completes
actual = {
    'cpu_cores': 16,
    'memory_gb': 28.5,
    'duration_sec': 3600,
    'peak_memory_gb': 28.5,
    'avg_cpu_utilization': 0.85
}
store_job_metrics('12345', design_params, actual)
```

---

## Formatting Guidelines for AWS Blog Publication

When preparing the blog post content:

- **InlineCode style**: Use for highlighting syntax elements, commands, and technical terms inline (e.g., `sbatch`, `slurmctld`, `r8.xlarge`)
- **Code style**: Use for blocks of code, YAML configurations, or multi-line syntax examples
- **No decorations**: Do not add borders, color-coding, or other visual decorations to code blocks - AWS blog editors will apply consistent styling during publication
- **Plain formatting**: Keep code blocks simple and undecorated to speed up the staging process


---

## Conclusion

In this post, we explored an ML-driven architecture for recovering over 90% of wasted compute capacity in HPC and EDA workloads on AWS. By combining intelligent resource prediction with continuous learning from actual job execution, this system eliminates out-of-memory failures and matches workloads to optimal instance types based on their specific characteristics. The architecture leverages AWS ParallelCluster with SLURM scheduling, Singularity containerization for secure and efficient workload execution, and a closed-loop feedback system that progressively improves predictions over time.

The key components—job submission plugins, ML-based prediction APIs, real-time resource monitoring, and automated feedback loops—work together to transform how HPC clusters allocate resources. Instead of users guessing requirements and over-provisioning "to be safe," the system learns from every job execution and applies that knowledge to optimize future submissions. Engineering and HPC teams already have deep expertise in this and can align their ML workflows to this mechanism. This approach is extensible beyond EDA tools to other HPC applications including Ansys, GROMACS, and LAMMPS, and can be deployed across multiple AWS compute platforms including ParallelCluster, AWS PCS, and AWS Batch.

### Next Steps

Ready to implement this solution in your environment? Here are your next steps:

1. **Try the demo code**: Visit our GitHub repository [link to repository] for production-ready deployment scripts, configuration templates, and example workloads you can run in your own AWS account.

2. **Start with AWS ParallelCluster**: Follow the Quick Start guide to deploy a basic cluster with SLURM, install the monitoring components, and run your first optimized jobs. You can start small with a few compute nodes and scale as you validate the approach.

3. **Explore AWS PCS**: For a fully managed experience, check out AWS Parallel Computing Service (PCS) which provides managed SLURM clusters with built-in support for the components described in this architecture.

4. **Extend to your workloads**: The prediction engine and monitoring framework are designed to be workload-agnostic. Adapt the feature extraction and model training to your specific applications, whether EDA, computational fluid dynamics, molecular dynamics, or other HPC domains.

### Related Content

- **AWS ParallelCluster Documentation**: Learn more about deploying and managing HPC clusters on AWS
- **Amazon FSx for Lustre**: High-performance file systems for compute-intensive workloads
- **AWS Batch**: Container-based batch computing for flexible workload execution
- **SLURM Workload Manager**: Open-source job scheduling for HPC clusters
- **Singularity/Apptainer**: Container platform designed for HPC environments

### Learn More

For questions, feedback, or to share your implementation experiences, reach out to the AWS HPC team or join the AWS HPC community forums. We're excited to see how you apply these techniques to optimize your own workloads and recover wasted compute capacity in your environment.

