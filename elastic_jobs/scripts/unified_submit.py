#!/usr/bin/env python3
"""
Unified job submission that automatically routes to the best allocation strategy:
- Predictive allocation for single-node workloads (OpenROAD, synthesis)
- Elastic jobs for parallel MPI workloads (simulations, verification)
- Job arrays for embarrassingly parallel workloads (parameter sweeps)
"""

import argparse
import subprocess
import sys
import json
from pathlib import Path

# Tool classification
SINGLE_NODE_TOOLS = [
    'openroad', 'innovus', 'genus', 'dc_shell', 'synthesis', 'place_route'
]

PARALLEL_MPI_TOOLS = [
    'corner_analysis', 'monte_carlo', 'hspice_parallel', 'calibre_distributed',
    'primetime_dmsa', 'power_analysis'
]

ARRAY_TOOLS = [
    'parameter_sweep', 'design_variants', 'regression_tests'
]

def classify_workload(tool):
    """Determine which allocation strategy to use"""
    if tool in SINGLE_NODE_TOOLS:
        return 'predictive'
    elif tool in PARALLEL_MPI_TOOLS:
        return 'elastic'
    elif tool in ARRAY_TOOLS:
        return 'array'
    else:
        # Default to predictive for unknown tools
        return 'predictive'

def predict_resources(design_params):
    """Use ML model to predict resource needs for single-node jobs"""
    try:
        # Try to load existing model
        import pickle
        import numpy as np
        
        model_path = Path('prediction/ridge_model.pkl')
        if model_path.exists():
            with open(model_path, 'rb') as f:
                model = pickle.load(f)
            
            # Predict based on design parameters
            gates = design_params.get('gates', 10000)
            nets = design_params.get('nets', int(gates * 0.9))
            
            X = np.array([[gates, nets]])
            pred = model.predict(X)[0]
            
            return {
                'cpu_percent': pred[0],
                'memory_mb': pred[1],
                'runtime_sec': pred[2]
            }
    except Exception as e:
        print(f"Warning: Could not load ML model: {e}")
    
    # Fallback: formula-based prediction
    gates = design_params.get('gates', 10000)
    memory_mb = 2000 + (gates * 0.08)  # Base + 0.08 MB per gate
    memory_mb *= 1.2  # 20% buffer
    
    return {
        'cpu_percent': 150,  # 1.5 cores
        'memory_mb': memory_mb,
        'runtime_sec': 300
    }

def submit_predictive(tool, params):
    """Submit single-node job with ML-predicted resources"""
    print(f"Strategy: Predictive Allocation (single-node)")
    print(f"  Tool: {tool}")
    
    # Predict resources
    predicted = predict_resources(params)
    memory_gb = int(predicted['memory_mb'] / 1024) + 1
    cpus = max(1, int(predicted['cpu_percent'] / 100) + 1)
    
    print(f"  Predicted: {memory_gb}GB memory, {cpus} CPUs")
    
    # Create job script
    script = f"""#!/bin/bash
#SBATCH --job-name={tool}_{params.get('design', 'test')}
#SBATCH --nodes=1
#SBATCH --cpus-per-task={cpus}
#SBATCH --mem={memory_gb}G
#SBATCH --time=02:00:00
#SBATCH --output={tool}_%j.out

echo "Predictive Allocation Job"
echo "Tool: {tool}"
echo "Design: {params.get('design', 'test')}"
echo "Allocated: {memory_gb}GB, {cpus} CPUs"
echo ""

# Run tool (placeholder - replace with actual tool invocation)
if [ "{tool}" == "openroad" ]; then
    echo "Running OpenROAD..."
    # openroad -no_init design.tcl
    echo "Simulating workload..."
    stress-ng --cpu {cpus} --vm 1 --vm-bytes {int(memory_gb * 0.7)}G --timeout 60s
else
    echo "Running {tool}..."
    sleep 60
fi

echo "Completed: $(date)"
"""
    
    script_name = f"{tool}_{params.get('design', 'test')}.sh"
    Path(script_name).write_text(script)
    
    # Submit
    result = subprocess.run(['sbatch', script_name], capture_output=True, text=True)
    if result.returncode == 0:
        job_id = result.stdout.strip().split()[-1]
        print(f"✓ Job submitted: {job_id}")
        return job_id
    else:
        print(f"✗ Submission failed: {result.stderr}")
        return None

def submit_elastic(tool, params):
    """Submit elastic MPI job with dynamic node scaling"""
    print(f"Strategy: Elastic Jobs (dynamic scaling)")
    print(f"  Tool: {tool}")
    
    # Map tool to workload type
    workload_map = {
        'corner_analysis': 'corner_analysis',
        'monte_carlo': 'monte_carlo',
        'hspice_parallel': 'monte_carlo',
        'parameter_sweep': 'parameter_sweep',
    }
    
    workload = workload_map.get(tool, 'corner_analysis')
    
    # Build command
    cmd = [
        'python3', 'elastic_jobs/scripts/submit_elastic.py',
        '--workload', workload,
        '--design', params.get('design', 'test')
    ]
    
    # Add workload-specific parameters
    if 'corners' in params:
        cmd.extend(['--corners', params['corners']])
    if 'voltages' in params:
        cmd.extend(['--voltages', params['voltages']])
    if 'temps' in params:
        cmd.extend(['--temps', params['temps']])
    if 'samples' in params:
        cmd.extend(['--samples', str(params['samples'])])
    if 'variants' in params:
        cmd.extend(['--variants', str(params['variants'])])
    
    # Submit
    result = subprocess.run(cmd, capture_output=True, text=True)
    print(result.stdout)
    
    if result.returncode == 0:
        # Extract job ID from output
        for line in result.stdout.split('\n'):
            if 'Job submitted:' in line:
                job_id = line.split(':')[-1].strip()
                return job_id
    
    return None

def submit_array(tool, params):
    """Submit job array for embarrassingly parallel workloads"""
    print(f"Strategy: Job Array (independent tasks)")
    print(f"  Tool: {tool}")
    
    array_size = params.get('variants', 100)
    print(f"  Array size: {array_size}")
    
    # Create job script
    script = f"""#!/bin/bash
#SBATCH --job-name={tool}_array
#SBATCH --array=1-{array_size}
#SBATCH --nodes=1
#SBATCH --cpus-per-task=4
#SBATCH --mem=8G
#SBATCH --time=01:00:00
#SBATCH --output={tool}_array_%A_%a.out

echo "Job Array Task"
echo "Array Job ID: $SLURM_ARRAY_JOB_ID"
echo "Array Task ID: $SLURM_ARRAY_TASK_ID"
echo "Design: {params.get('design', 'test')}_$SLURM_ARRAY_TASK_ID"
echo ""

# Run task (placeholder)
echo "Processing variant $SLURM_ARRAY_TASK_ID..."
sleep 30

echo "Completed: $(date)"
"""
    
    script_name = f"{tool}_array.sh"
    Path(script_name).write_text(script)
    
    # Submit
    result = subprocess.run(['sbatch', script_name], capture_output=True, text=True)
    if result.returncode == 0:
        job_id = result.stdout.strip().split()[-1]
        print(f"✓ Job array submitted: {job_id}")
        return job_id
    else:
        print(f"✗ Submission failed: {result.stderr}")
        return None

def main():
    parser = argparse.ArgumentParser(
        description='Unified job submission - automatically selects best strategy'
    )
    
    parser.add_argument('--tool', required=True, help='Tool/workload type')
    parser.add_argument('--design', default='test_design', help='Design name')
    
    # Single-node parameters
    parser.add_argument('--gates', type=int, help='Number of gates (for prediction)')
    parser.add_argument('--nets', type=int, help='Number of nets (for prediction)')
    
    # Parallel workload parameters
    parser.add_argument('--corners', help='Process corners (comma-separated)')
    parser.add_argument('--voltages', help='Voltages (comma-separated)')
    parser.add_argument('--temps', help='Temperatures (comma-separated)')
    parser.add_argument('--samples', type=int, help='Monte Carlo samples')
    parser.add_argument('--variants', type=int, help='Number of variants')
    
    parser.add_argument('--force-strategy', choices=['predictive', 'elastic', 'array'],
                       help='Force specific strategy (override auto-detection)')
    
    args = parser.parse_args()
    
    # Build parameters dict
    params = {
        'design': args.design,
        'gates': args.gates,
        'nets': args.nets,
        'corners': args.corners,
        'voltages': args.voltages,
        'temps': args.temps,
        'samples': args.samples,
        'variants': args.variants,
    }
    
    # Remove None values
    params = {k: v for k, v in params.items() if v is not None}
    
    print("=" * 60)
    print("Unified Job Submission")
    print("=" * 60)
    
    # Determine strategy
    if args.force_strategy:
        strategy = args.force_strategy
        print(f"Strategy: {strategy} (forced)")
    else:
        strategy = classify_workload(args.tool)
        print(f"Strategy: {strategy} (auto-detected)")
    
    print()
    
    # Route to appropriate submission method
    if strategy == 'predictive':
        job_id = submit_predictive(args.tool, params)
    elif strategy == 'elastic':
        job_id = submit_elastic(args.tool, params)
    elif strategy == 'array':
        job_id = submit_array(args.tool, params)
    
    if job_id:
        print()
        print("=" * 60)
        print(f"✓ Success! Job ID: {job_id}")
        print("=" * 60)
        return 0
    else:
        print()
        print("=" * 60)
        print("✗ Submission failed")
        print("=" * 60)
        return 1

if __name__ == '__main__':
    sys.exit(main())
