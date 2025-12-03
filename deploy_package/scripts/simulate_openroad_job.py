#!/usr/bin/env python3
"""
Simulate OpenROAD job execution for local testing
Uses CPU/memory intensive operations to simulate EDA workload
"""

import sys
import time
import argparse
import numpy as np
from pathlib import Path

# Add monitoring to path
sys.path.append(str(Path(__file__).parent.parent))
from monitoring.resource_monitor import JobMonitor, monitor_command, save_metrics


def simulate_synthesis(cell_count: int, clock_freq_mhz: int, tech_node_nm: int, duration: int = 5):
    """
    Simulate synthesis stage - CPU intensive
    Higher frequency and smaller nodes require more optimization iterations
    """
    print(f"[SYNTHESIS] Processing {cell_count} cells at {clock_freq_mhz}MHz, {tech_node_nm}nm...")
    
    # Scale duration based on frequency (higher freq = more optimization)
    freq_factor = clock_freq_mhz / 100.0  # Normalize to 100MHz
    tech_factor = 130.0 / tech_node_nm  # Smaller nodes are harder (inverse)
    adjusted_duration = duration * freq_factor * tech_factor
    
    # CPU-intensive work
    start = time.time()
    iterations = int(cell_count / 100)  # More cells = more work
    while time.time() - start < adjusted_duration:
        # Matrix operations to use CPU (size scales with complexity)
        matrix_size = min(1000 + int(freq_factor * 200), 2000)
        _ = np.random.rand(matrix_size, matrix_size) @ np.random.rand(matrix_size, matrix_size)
        time.sleep(0.05)
    
    print(f"[SYNTHESIS] Complete ({time.time() - start:.1f}s)")


def simulate_placement(cell_count: int, utilization: float, clock_freq_mhz: int, 
                       tech_node_nm: int, duration: int = 8):
    """
    Simulate placement stage - Memory and CPU intensive
    Higher utilization and frequency increase memory and runtime
    """
    print(f"[PLACEMENT] Placing {cell_count} cells at {utilization*100}% util, {clock_freq_mhz}MHz, {tech_node_nm}nm...")
    
    # Memory scales with cell count and utilization
    # Higher utilization = tighter packing = more memory for optimization
    memory_mb = int(cell_count / 1000 * (1 + utilization))
    
    # Duration scales with frequency (timing closure harder at high freq)
    freq_factor = clock_freq_mhz / 100.0
    util_factor = utilization / 0.6  # Normalize to 60%
    tech_factor = 130.0 / tech_node_nm
    adjusted_duration = duration * freq_factor * util_factor * tech_factor
    
    data = []
    start = time.time()
    while time.time() - start < adjusted_duration:
        # Allocate memory
        if len(data) < memory_mb:
            data.append(np.random.rand(1024, 128))  # ~1MB chunks
        
        # CPU work (more intense for high frequency designs)
        cpu_size = min(500 + int(freq_factor * 100), 800)
        _ = np.random.rand(cpu_size, cpu_size) @ np.random.rand(cpu_size, cpu_size)
        time.sleep(0.05)
    
    print(f"[PLACEMENT] Complete ({time.time() - start:.1f}s, {len(data)}MB allocated)")


def simulate_routing(net_count: int, clock_freq_mhz: int, tech_node_nm: int, 
                     utilization: float, duration: int = 10):
    """
    Simulate routing stage - I/O and memory intensive
    Smaller nodes have more routing layers and complexity
    """
    print(f"[ROUTING] Routing {net_count} nets at {tech_node_nm}nm...")
    
    # Routing complexity increases with:
    # - More nets
    # - Higher frequency (tighter timing constraints)
    # - Smaller nodes (more layers, tighter rules)
    # - Higher utilization (more congestion)
    freq_factor = clock_freq_mhz / 100.0
    tech_factor = 130.0 / tech_node_nm
    util_factor = utilization / 0.6
    adjusted_duration = duration * freq_factor * tech_factor * util_factor
    
    # Create temporary files to simulate I/O
    temp_dir = Path('data/temp')
    temp_dir.mkdir(parents=True, exist_ok=True)
    
    start = time.time()
    file_count = 0
    io_size = int(1000 * tech_factor)  # Smaller nodes = more data
    
    while time.time() - start < adjusted_duration:
        # Write data to simulate I/O
        temp_file = temp_dir / f"route_{file_count}.tmp"
        data = np.random.rand(io_size, 100)
        np.save(temp_file, data)
        file_count += 1
        
        # CPU work
        cpu_size = min(300 + int(freq_factor * 50), 500)
        _ = np.random.rand(cpu_size, cpu_size) @ np.random.rand(cpu_size, cpu_size)
        time.sleep(0.1)
    
    # Cleanup
    for f in temp_dir.glob('*.tmp'):
        f.unlink()
    
    print(f"[ROUTING] Complete ({time.time() - start:.1f}s, {file_count} routing iterations)")


def run_simulated_job(design_name: str, design_features: dict, tool_config: dict):
    """Run a complete simulated OpenROAD job"""
    
    print(f"\n{'='*60}")
    print(f"Starting job: {design_name}")
    print(f"Cell count: {design_features['cell_count']}")
    print(f"Frequency: {design_features['clock_freq_mhz']} MHz")
    print(f"Technology: {design_features['technology_node_nm']} nm")
    print(f"Utilization: {design_features['utilization_target']*100}%")
    print(f"{'='*60}\n")
    
    # Create job monitor
    job_monitor = JobMonitor(design_name, design_features, tool_config)
    
    # Extract parameters
    cell_count = design_features['cell_count']
    net_count = design_features['net_count']
    clock_freq = design_features['clock_freq_mhz']
    tech_node = design_features['technology_node_nm']
    utilization = design_features['utilization_target']
    
    # Run stages with monitoring
    # Note: We use Python functions instead of external commands for simulation
    
    # Synthesis
    monitor_command(
        ['python3', '-c', 
         f'import sys; sys.path.append("scripts"); from simulate_openroad_job import simulate_synthesis; simulate_synthesis({cell_count}, {clock_freq}, {tech_node}, 5)'],
        'synthesis',
        job_monitor
    )
    
    # Placement
    monitor_command(
        ['python3', '-c',
         f'import sys; sys.path.append("scripts"); from simulate_openroad_job import simulate_placement; simulate_placement({cell_count}, {utilization}, {clock_freq}, {tech_node}, 8)'],
        'placement',
        job_monitor
    )
    
    # Routing
    monitor_command(
        ['python3', '-c',
         f'import sys; sys.path.append("scripts"); from simulate_openroad_job import simulate_routing; simulate_routing({net_count}, {clock_freq}, {tech_node}, {utilization}, 10)'],
        'routing',
        job_monitor
    )
    
    # Finalize and save metrics
    metrics = job_monitor.finalize()
    
    output_file = Path(f'data/metrics/{design_name}.json')
    save_metrics(metrics, output_file)
    
    print(f"\n{'='*60}")
    print(f"Job {design_name} completed!")
    print(f"Total duration: {metrics['total_duration_sec']:.1f}s")
    print(f"Metrics saved to: {output_file}")
    print(f"{'='*60}\n")


def main():
    parser = argparse.ArgumentParser(description='Simulate OpenROAD job')
    parser.add_argument('--name', default='test_design', help='Design name')
    parser.add_argument('--cells', type=int, default=10000, help='Cell count')
    parser.add_argument('--freq', type=int, default=100, help='Clock frequency (MHz)')
    parser.add_argument('--util', type=float, default=0.6, help='Utilization target')
    parser.add_argument('--tech', type=int, default=130, help='Technology node (nm)')
    parser.add_argument('--clock-gating', action='store_true', help='Enable clock gating')
    
    args = parser.parse_args()
    
    # Infer technology node from name if not specified
    tech_node = args.tech
    if '45nm' in args.name:
        tech_node = 45
    elif '7nm' in args.name:
        tech_node = 7
    
    design_features = {
        'cell_count': args.cells,
        'net_count': int(args.cells * 0.9),  # Typical ratio
        'die_area_um2': args.cells * 200,  # Rough estimate
        'utilization_target': args.util,
        'aspect_ratio': 1.0,
        'clock_freq_mhz': args.freq,
        'clock_domains': 1,
        'technology_node_nm': tech_node,
        'metal_layers': 6 if tech_node >= 45 else 10,  # More layers for advanced nodes
        'clock_gating_enabled': args.clock_gating,
        'power_gating_enabled': False,
        'hierarchy_depth': 3,
        'macro_count': 0
    }
    
    tool_config = {
        'tool': 'openroad',
        'threads': 4,
        'version': 'simulated'
    }
    
    run_simulated_job(args.name, design_features, tool_config)


if __name__ == "__main__":
    main()
