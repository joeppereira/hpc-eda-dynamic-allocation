#!/usr/bin/env python3
"""
Smart job submission with automatic memory calculation
Usage: python3 smart_submit.py --gates 100000 --script job.sh
"""

import argparse
import subprocess
import sys

def calculate_memory_mb(gates):
    """Calculate required memory based on gate count"""
    base_mb = 2000
    calculated_mb = base_mb + (gates * 0.08)
    buffer_mb = calculated_mb * 0.2
    total_mb = int(calculated_mb + buffer_mb)
    return total_mb

def submit_job(gates, script, **kwargs):
    """Submit job with calculated memory"""
    memory_mb = calculate_memory_mb(gates)
    memory_gb = memory_mb / 1024
    
    print(f"Design: {gates:,} gates")
    print(f"Calculated memory: {memory_mb} MB ({memory_gb:.1f} GB)")
    
    # Build sbatch command
    cmd = [
        'sbatch',
        f'--mem={memory_mb}M',
        f'--export=ALL,DESIGN_GATES={gates}'
    ]
    
    # Add optional parameters
    if kwargs.get('cpus'):
        cmd.append(f'--cpus-per-task={kwargs["cpus"]}')
    if kwargs.get('time'):
        cmd.append(f'--time={kwargs["time"]}')
    if kwargs.get('output'):
        cmd.append(f'--output={kwargs["output"]}')
    
    cmd.append(script)
    
    print(f"Submitting: {' '.join(cmd)}")
    result = subprocess.run(cmd, capture_output=True, text=True)
    
    if result.returncode == 0:
        print(f"✓ {result.stdout.strip()}")
        return True
    else:
        print(f"✗ Error: {result.stderr}")
        return False

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description='Smart SLURM job submission')
    parser.add_argument('--gates', type=int, required=True, help='Number of gates')
    parser.add_argument('--script', required=True, help='Job script to submit')
    parser.add_argument('--cpus', type=int, default=2, help='CPUs per task')
    parser.add_argument('--time', default='01:00:00', help='Time limit')
    parser.add_argument('--output', help='Output file pattern')
    
    args = parser.parse_args()
    
    success = submit_job(
        args.gates,
        args.script,
        cpus=args.cpus,
        time=args.time,
        output=args.output
    )
    
    sys.exit(0 if success else 1)
