# SLURM Elastic Jobs for HPC/EDA Workloads

This directory contains a complete implementation of SLURM elastic jobs for parallel HPC/EDA workloads that can benefit from dynamic node scaling.

## What Are Elastic Jobs?

Elastic jobs allow SLURM to dynamically **add or remove compute nodes** during job execution based on:
- Available cluster resources
- Workload demands
- Queue priorities

**Key benefit:** Total memory and CPU capacity scales with node count.

## When to Use Elastic Jobs

### ✅ Good Use Cases (Parallel/MPI Workloads)

- **Corner Analysis**: Multiple PVT corners analyzed in parallel
- **Monte Carlo Simulation**: Thousands of independent samples
- **Distributed Verification**: DRC/LVS across multiple nodes
- **Parameter Sweeps**: Design space exploration
- **Multi-scenario Analysis**: Power/timing across scenarios

### ❌ Bad Use Cases (Single-Node Workloads)

- **Place & Route**: Single-process, shared memory (use predictive allocation)
- **Synthesis**: Single-process (use predictive allocation)
- **Single-design jobs**: Cannot distribute across nodes

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│         Unified Job Submission System                   │
│  (Automatically routes to best allocation strategy)     │
└─────────────────────────────────────────────────────────┘
                          ↓
        ┌─────────────────┼─────────────────┐
        ↓                 ↓                  ↓
┌───────────────┐  ┌──────────────┐  ┌─────────────┐
│  Predictive   │  │   Elastic    │  │  Job Array  │
│  Allocation   │  │    Jobs      │  │             │
│               │  │              │  │             │
│ Single-node   │  │ MPI parallel │  │ Independent │
│ OpenROAD      │  │ Simulations  │  │ Sweeps      │
│ Synthesis     │  │ Verification │  │ Variants    │
└───────────────┘  └──────────────┘  └─────────────┘
```

## Directory Structure

```
elastic_jobs/
├── README.md                    # This file
├── examples/
│   ├── corner_analysis.py       # Parallel corner analysis
│   ├── monte_carlo_sim.py       # Monte Carlo simulation
│   └── parameter_sweep.py       # Design space exploration
├── scripts/
│   ├── submit_elastic.py        # Elastic job submission
│   ├── unified_submit.py        # Unified submission (routes to best strategy)
│   └── monitor_elastic.py       # Monitor elastic job scaling
├── aws/
│   ├── enable_elastic.sh        # Enable elastic jobs on ParallelCluster
│   ├── install_mpi.sh           # Install PMIx-enabled OpenMPI
│   └── test_elastic.sh          # Test elastic job functionality
├── tests/
│   ├── test_elastic_scaling.sh  # Verify dynamic scaling works
│   └── benchmark_elastic.py     # Compare elastic vs fixed allocation
└── docs/
    ├── ELASTIC_JOBS_GUIDE.md    # Detailed guide
    └── COMPARISON.md            # Elastic vs Predictive allocation
```

## Quick Start

### 1. Enable Elastic Jobs on Cluster

```bash
# On AWS ParallelCluster head node
cd elastic_jobs/aws
./enable_elastic.sh
./install_mpi.sh
```

### 2. Submit an Elastic Job

```bash
# Parallel corner analysis (2-10 nodes)
python3 scripts/submit_elastic.py \
  --workload corner_analysis \
  --min-nodes 2 \
  --max-nodes 10 \
  --design my_chip

# Monitor scaling
python3 scripts/monitor_elastic.py --job-id 12345
```

### 3. Use Unified Submission (Automatic Routing)

```bash
# Automatically selects best strategy
python3 scripts/unified_submit.py \
  --tool openroad \
  --design my_chip \
  --gates 100000

# Routes to predictive allocation (single-node)

python3 scripts/unified_submit.py \
  --tool corner_analysis \
  --corners ss,tt,ff \
  --voltages 0.7,0.8,0.9

# Routes to elastic jobs (parallel)
```

## Requirements

- SLURM 20.11+ (you have 24.11.6 ✅)
- PMIx-enabled MPI (OpenMPI 4.0+ or MPICH 3.4+)
- Elastic partition enabled in slurm.conf
- MPI-aware application

## Key Differences: Elastic vs Predictive

| Feature | Predictive Allocation | Elastic Jobs |
|---------|----------------------|--------------|
| **Node count** | Fixed (1 node) | Dynamic (min-max) |
| **Memory** | Predicted upfront | Scales with nodes |
| **CPUs** | Predicted upfront | Scales with nodes |
| **Use case** | Single-node jobs | Parallel MPI jobs |
| **Complexity** | Low | Medium |
| **Application changes** | None | Must be MPI-aware |

## Examples

### Example 1: Corner Analysis (Elastic)

```bash
# Analyze 27 corners (3 process × 3 voltage × 3 temp)
# Start with 2 nodes, grow to 10 if available

sbatch --nodes=2-10 corner_analysis.sh
```

**Scaling behavior:**
- Start: 2 nodes, 128GB total, analyze 8 corners in parallel
- Grow: 10 nodes, 640GB total, analyze 40 corners in parallel
- Shrink: 3 nodes, 192GB total, post-processing

### Example 2: OpenROAD (Predictive - Not Elastic)

```bash
# Single design, single node
# Use ML prediction for memory

python3 scripts/unified_submit.py \
  --tool openroad \
  --gates 100000 \
  --nets 90000
```

**Allocation:**
- Predicted: 12GB memory needed
- Allocated: 14.4GB (12GB × 1.2 buffer)
- Fixed for job duration

## Performance Benefits

### Elastic Jobs (Parallel Workloads)

```
Fixed allocation (10 nodes):
- Always reserves 10 nodes
- Wastes resources during startup/cleanup
- Cost: 10 nodes × 2 hours = 20 node-hours

Elastic allocation (2-10 nodes):
- Starts with 2 nodes (startup)
- Grows to 10 nodes (peak work)
- Shrinks to 3 nodes (cleanup)
- Cost: 2×0.5h + 10×1h + 3×0.5h = 12.5 node-hours
- Savings: 37.5%
```

## Monitoring

```bash
# Watch job scaling in real-time
watch -n 2 'squeue -j 12345 -o "%.18i %.8u %.10P %.8T %.6D %.20S"'

# View scaling history
sacct -j 12345 --format=JobID,Elapsed,NNodes,State,MaxRSS

# Detailed scaling events
python3 scripts/monitor_elastic.py --job-id 12345 --verbose
```

## Troubleshooting

### Job Not Scaling

```bash
# Check if elastic partition is enabled
scontrol show partition compute | grep Elastic

# Check PMIx support
mpirun --version | grep pmix

# View SLURM logs
tail -f /var/log/slurm/slurmctld.log | grep elastic
```

### Application Not Handling Dynamic Processes

Your MPI application must handle dynamic process changes:

```python
from mpi4py import MPI

comm = MPI.COMM_WORLD
rank = comm.Get_rank()

while work_remaining:
    # Re-check process count (may have changed!)
    size = comm.Get_size()
    
    # Redistribute work
    my_work = distribute_work(total_work, size, rank)
    process(my_work)
```

## Cost Analysis

### When Elastic Jobs Save Money

- **Variable workload intensity**: Startup/cleanup phases need fewer nodes
- **Opportunistic scaling**: Use nodes when available, shrink when busy
- **Adaptive complexity**: Some problems need more resources than others

### When Fixed Allocation is Better

- **Predictable workload**: Constant resource needs throughout
- **Short jobs**: Overhead of scaling not worth it
- **Single-node**: Cannot benefit from additional nodes

## Integration with Existing System

Elastic jobs **complement** your existing predictive allocation system:

```python
# Unified submission automatically chooses best strategy
if is_parallel_workload(job):
    submit_elastic(job)      # Use elastic scaling
else:
    submit_predictive(job)   # Use ML prediction
```

Both systems coexist and are used for different workload types.

## Next Steps

1. **Enable elastic jobs**: Run `aws/enable_elastic.sh`
2. **Test with examples**: Try `examples/corner_analysis.py`
3. **Monitor scaling**: Use `scripts/monitor_elastic.py`
4. **Integrate**: Add to your workflow with `scripts/unified_submit.py`

## References

- [SLURM Elastic Computing](https://slurm.schedmd.com/elastic_computing.html)
- [PMIx Documentation](https://pmix.github.io/)
- [OpenMPI Dynamic Processes](https://www.open-mpi.org/doc/current/)
