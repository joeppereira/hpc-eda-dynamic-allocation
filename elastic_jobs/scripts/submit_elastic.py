#!/usr/bin/env python3
"""
Submit elastic SLURM jobs for parallel HPC/EDA workloads.

This script submits jobs that can dynamically scale between min and max nodes
based on cluster availability and workload demands.
"""

import argparse
import subprocess
import sys
from pathlib import Path

def estimate_node_range(workload_type, params):
    """Estimate min/max nodes based on workload characteristics"""
    
    if workload_type == "corner_analysis":
        # Calculate total scenarios
        corners = len(params.get('corners', 'ss,tt,ff').split(','))
        voltages = len(params.get('voltages', '0.7,0.8,0.9').split(','))
        temps = len(params.get('temps', '-40,25,125').split(','))
        total_scenarios = corners * voltages * temps
        
        # 1 node per 4 scenarios, min 2, max 20
        min_nodes = 2
        max_nodes = min(20, max(2, total_scenarios // 4))
        
    elif workload_type == "monte_carlo":
        samples = params.get('samples', 1000)
        # 1 node per 100 samples, min 2, max 50
        min_nodes = 2
        max_nodes = min(50, max(2, samples // 100))
        
    elif workload_type == "parameter_sweep":
        variants = params.get('variants', 100)
        # 1 node per 10 variants, min 1, max 20
        min_nodes = 1
        max_nodes = min(20, max(1, variants // 10))
        
    else:
        # Default conservative range
        min_nodes = 2
        max_nodes = 10
    
    return min_nodes, max_nodes

def create_elastic_job_script(workload_type, params, min_nodes, max_nodes):
    """Generate SLURM job script for elastic execution"""
    
    job_name = params.get('job_name', f'elastic_{workload_type}')
    time_limit = params.get('time_limit', '02:00:00')
    tasks_per_node = params.get('tasks_per_node', 4)
    
    script = f"""#!/bin/bash
#SBATCH --job-name={job_name}
#SBATCH --nodes={min_nodes}-{max_nodes}
#SBATCH --ntasks-per-node={tasks_per_node}
#SBATCH --mem=0
#SBATCH --time={time_limit}
#SBATCH --output=elastic_{job_name}_%j.out
#SBATCH --error=elastic_{job_name}_%j.err

# Load MPI module
module load openmpi/4.1.6 || true

echo "=========================================="
echo "Elastic Job: {job_name}"
echo "=========================================="
echo "Job ID: $SLURM_JOB_ID"
echo "Started: $(date)"
echo "Initial nodes: $SLURM_JOB_NUM_NODES"
echo "Initial tasks: $SLURM_NTASKS"
echo "Node range: {min_nodes}-{max_nodes}"
echo ""

# Log node allocation over time
log_nodes() {{
    while true; do
        echo "[$(date +%H:%M:%S)] Nodes: $SLURM_JOB_NUM_NODES, Tasks: $SLURM_NTASKS"
        sleep 30
    done
}}
log_nodes &
LOG_PID=$!

"""
    
    # Add workload-specific execution
    if workload_type == "corner_analysis":
        script += f"""
# Run parallel corner analysis
echo "Running corner analysis..."
echo "Corners: {params.get('corners', 'ss,tt,ff')}"
echo "Voltages: {params.get('voltages', '0.7,0.8,0.9')}"
echo "Temps: {params.get('temps', '-40,25,125')}"
echo ""

# Execute with PMIx-enabled MPI
mpirun --mca pmix_base_verbose 10 \\
    python3 elastic_jobs/examples/corner_analysis.py \\
    --design {params.get('design', 'test_design')} \\
    --corners {params.get('corners', 'ss,tt,ff')} \\
    --voltages {params.get('voltages', '0.7,0.8,0.9')} \\
    --temps {params.get('temps', '-40,25,125')}
"""
    
    elif workload_type == "monte_carlo":
        script += f"""
# Run Monte Carlo simulation
echo "Running Monte Carlo simulation..."
echo "Samples: {params.get('samples', 1000)}"
echo ""

mpirun --mca pmix_base_verbose 10 \\
    python3 elastic_jobs/examples/monte_carlo_sim.py \\
    --design {params.get('design', 'test_design')} \\
    --samples {params.get('samples', 1000)}
"""
    
    elif workload_type == "parameter_sweep":
        script += f"""
# Run parameter sweep
echo "Running parameter sweep..."
echo "Variants: {params.get('variants', 100)}"
echo ""

mpirun --mca pmix_base_verbose 10 \\
    python3 elastic_jobs/examples/parameter_sweep.py \\
    --design {params.get('design', 'test_design')} \\
    --variants {params.get('variants', 100)}
"""
    
    script += """
# Stop logging
kill $LOG_PID 2>/dev/null

echo ""
echo "=========================================="
echo "Job completed: $(date)"
echo "Final nodes: $SLURM_JOB_NUM_NODES"
echo "=========================================="
"""
    
    return script

def submit_job(script_content, script_name):
    """Write script and submit to SLURM"""
    
    # Write script file
    script_path = Path(script_name)
    script_path.write_text(script_content)
    script_path.chmod(0o755)
    
    # Submit to SLURM
    result = subprocess.run(
        ['sbatch', str(script_path)],
        capture_output=True,
        text=True
    )
    
    if result.returncode == 0:
        # Extract job ID
        job_id = result.stdout.strip().split()[-1]
        return job_id
    else:
        print(f"Error submitting job: {result.stderr}", file=sys.stderr)
        return None

def main():
    parser = argparse.ArgumentParser(
        description='Submit elastic SLURM jobs for parallel workloads'
    )
    
    parser.add_argument(
        '--workload',
        required=True,
        choices=['corner_analysis', 'monte_carlo', 'parameter_sweep'],
        help='Type of workload to run'
    )
    
    parser.add_argument('--design', default='test_design', help='Design name')
    parser.add_argument('--job-name', help='Job name (default: elastic_<workload>)')
    parser.add_argument('--time-limit', default='02:00:00', help='Time limit (HH:MM:SS)')
    parser.add_argument('--tasks-per-node', type=int, default=4, help='Tasks per node')
    
    # Workload-specific parameters
    parser.add_argument('--min-nodes', type=int, help='Minimum nodes (auto-calculated if not set)')
    parser.add_argument('--max-nodes', type=int, help='Maximum nodes (auto-calculated if not set)')
    
    # Corner analysis parameters
    parser.add_argument('--corners', default='ss,tt,ff', help='Process corners (comma-separated)')
    parser.add_argument('--voltages', default='0.7,0.8,0.9', help='Voltages (comma-separated)')
    parser.add_argument('--temps', default='-40,25,125', help='Temperatures (comma-separated)')
    
    # Monte Carlo parameters
    parser.add_argument('--samples', type=int, default=1000, help='Number of Monte Carlo samples')
    
    # Parameter sweep parameters
    parser.add_argument('--variants', type=int, default=100, help='Number of design variants')
    
    parser.add_argument('--dry-run', action='store_true', help='Print script without submitting')
    
    args = parser.parse_args()
    
    # Build parameters dict
    params = {
        'design': args.design,
        'job_name': args.job_name or f'elastic_{args.workload}',
        'time_limit': args.time_limit,
        'tasks_per_node': args.tasks_per_node,
        'corners': args.corners,
        'voltages': args.voltages,
        'temps': args.temps,
        'samples': args.samples,
        'variants': args.variants,
    }
    
    # Estimate or use provided node range
    if args.min_nodes and args.max_nodes:
        min_nodes = args.min_nodes
        max_nodes = args.max_nodes
    else:
        min_nodes, max_nodes = estimate_node_range(args.workload, params)
    
    print(f"Submitting elastic {args.workload} job")
    print(f"  Design: {args.design}")
    print(f"  Node range: {min_nodes}-{max_nodes}")
    print(f"  Tasks per node: {args.tasks_per_node}")
    print()
    
    # Create job script
    script = create_elastic_job_script(args.workload, params, min_nodes, max_nodes)
    script_name = f"elastic_{args.workload}_{args.design}.sh"
    
    if args.dry_run:
        print("Generated script:")
        print("=" * 60)
        print(script)
        print("=" * 60)
        return 0
    
    # Submit job
    job_id = submit_job(script, script_name)
    
    if job_id:
        print(f"✓ Job submitted: {job_id}")
        print(f"  Script: {script_name}")
        print()
        print("Monitor with:")
        print(f"  watch -n 2 'squeue -j {job_id}'")
        print(f"  python3 elastic_jobs/scripts/monitor_elastic.py --job-id {job_id}")
        return 0
    else:
        print("✗ Job submission failed", file=sys.stderr)
        return 1

if __name__ == '__main__':
    sys.exit(main())
