#!/usr/bin/env python3
"""
Monitor elastic job scaling in real-time.
Shows how node count changes during job execution.
"""

import argparse
import subprocess
import time
import sys
from datetime import datetime

def get_job_info(job_id):
    """Get current job information from SLURM"""
    try:
        result = subprocess.run(
            ['scontrol', 'show', 'job', str(job_id)],
            capture_output=True,
            text=True,
            timeout=5
        )
        
        if result.returncode != 0:
            return None
        
        # Parse output
        info = {}
        for line in result.stdout.split('\n'):
            for item in line.split():
                if '=' in item:
                    key, value = item.split('=', 1)
                    info[key] = value
        
        return info
    except Exception as e:
        print(f"Error getting job info: {e}", file=sys.stderr)
        return None

def get_job_history(job_id):
    """Get job history from sacct"""
    try:
        result = subprocess.run(
            ['sacct', '-j', str(job_id), '--format=JobID,Elapsed,NNodes,State,MaxRSS', '-P'],
            capture_output=True,
            text=True,
            timeout=5
        )
        
        if result.returncode != 0:
            return []
        
        lines = result.stdout.strip().split('\n')
        if len(lines) < 2:
            return []
        
        # Parse header and data
        header = lines[0].split('|')
        data = []
        for line in lines[1:]:
            values = line.split('|')
            if len(values) == len(header):
                data.append(dict(zip(header, values)))
        
        return data
    except Exception as e:
        print(f"Error getting job history: {e}", file=sys.stderr)
        return []

def monitor_job(job_id, interval=5, verbose=False):
    """Monitor job scaling in real-time"""
    
    print(f"Monitoring elastic job: {job_id}")
    print(f"Update interval: {interval} seconds")
    print(f"Press Ctrl+C to stop")
    print()
    print("=" * 80)
    
    scaling_history = []
    last_node_count = None
    
    try:
        while True:
            info = get_job_info(job_id)
            
            if info is None:
                print(f"\n[{datetime.now().strftime('%H:%M:%S')}] Job not found or completed")
                break
            
            # Extract key information
            state = info.get('JobState', 'UNKNOWN')
            nodes = info.get('NumNodes', '0')
            cpus = info.get('NumCPUs', '0')
            elapsed = info.get('RunTime', '00:00:00')
            
            # Track scaling events
            try:
                node_count = int(nodes)
                if last_node_count is not None and node_count != last_node_count:
                    scaling_history.append({
                        'time': datetime.now(),
                        'elapsed': elapsed,
                        'from_nodes': last_node_count,
                        'to_nodes': node_count,
                        'change': node_count - last_node_count
                    })
                    
                    print()
                    print("!" * 80)
                    if node_count > last_node_count:
                        print(f"SCALING UP: {last_node_count} → {node_count} nodes (+{node_count - last_node_count})")
                    else:
                        print(f"SCALING DOWN: {last_node_count} → {node_count} nodes ({node_count - last_node_count})")
                    print("!" * 80)
                    print()
                
                last_node_count = node_count
            except ValueError:
                pass
            
            # Display current status
            timestamp = datetime.now().strftime('%H:%M:%S')
            print(f"[{timestamp}] State: {state:12} | Nodes: {nodes:4} | CPUs: {cpus:6} | Elapsed: {elapsed}", end='')
            
            if verbose and info:
                print()
                print(f"           NodeList: {info.get('NodeList', 'N/A')}")
            else:
                print()
            
            # Check if job is done
            if state in ['COMPLETED', 'FAILED', 'CANCELLED', 'TIMEOUT']:
                print()
                print(f"Job finished with state: {state}")
                break
            
            time.sleep(interval)
    
    except KeyboardInterrupt:
        print("\n\nMonitoring stopped by user")
    
    # Show scaling summary
    if scaling_history:
        print()
        print("=" * 80)
        print("SCALING EVENTS SUMMARY")
        print("=" * 80)
        for i, event in enumerate(scaling_history, 1):
            direction = "↑ UP" if event['change'] > 0 else "↓ DOWN"
            print(f"{i}. [{event['time'].strftime('%H:%M:%S')}] {direction:6} | "
                  f"{event['from_nodes']} → {event['to_nodes']} nodes | "
                  f"Elapsed: {event['elapsed']}")
        
        print()
        print(f"Total scaling events: {len(scaling_history)}")
        
        # Calculate node-hours
        print()
        print("Resource Usage:")
        history = get_job_history(job_id)
        if history:
            for entry in history:
                if entry.get('JobID') == str(job_id):
                    print(f"  Elapsed: {entry.get('Elapsed', 'N/A')}")
                    print(f"  Max Nodes: {entry.get('NNodes', 'N/A')}")
                    print(f"  Max Memory: {entry.get('MaxRSS', 'N/A')}")
    else:
        print()
        print("No scaling events detected (job may have run with fixed node count)")
    
    print("=" * 80)

def main():
    parser = argparse.ArgumentParser(
        description='Monitor elastic SLURM job scaling'
    )
    
    parser.add_argument(
        '--job-id',
        required=True,
        help='SLURM job ID to monitor'
    )
    
    parser.add_argument(
        '--interval',
        type=int,
        default=5,
        help='Update interval in seconds (default: 5)'
    )
    
    parser.add_argument(
        '--verbose',
        action='store_true',
        help='Show detailed information'
    )
    
    args = parser.parse_args()
    
    monitor_job(args.job_id, args.interval, args.verbose)
    
    return 0

if __name__ == '__main__':
    sys.exit(main())
