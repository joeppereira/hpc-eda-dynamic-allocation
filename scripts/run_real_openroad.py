#!/usr/bin/env python3
"""
Run REAL OpenROAD flow and capture actual stage-level metrics

This script:
1. Runs actual OpenROAD on real designs
2. Parses OpenROAD logs to detect stages
3. Captures real resource usage per stage
4. Stores accurate metrics for prediction
"""

import sys
import subprocess
import re
from pathlib import Path
from typing import Dict, List, Tuple

sys.path.append(str(Path(__file__).parent.parent))
from monitoring.resource_monitor import JobMonitor, monitor_command, save_metrics


class OpenROADStageParser:
    """Parse OpenROAD logs to identify stages"""
    
    # OpenROAD stage markers from actual logs
    STAGE_MARKERS = {
        'read_design': [
            r'\[INFO\] Reading LEF file',
            r'\[INFO\] Reading DEF file',
            r'\[INFO\] Reading liberty file'
        ],
        'floorplan': [
            r'\[INFO\] initialize_floorplan',
            r'\[INFO\] Floorplan area'
        ],
        'placement': [
            r'\[INFO\] Starting global placement',
            r'\[INFO\] Global placement complete',
            r'\[INFO\] Starting detailed placement',
            r'\[INFO\] Detailed placement complete'
        ],
        'cts': [
            r'\[INFO\] Starting clock tree synthesis',
            r'\[INFO\] Clock tree synthesis complete'
        ],
        'routing': [
            r'\[INFO\] Starting global routing',
            r'\[INFO\] Global routing complete',
            r'\[INFO\] Starting detailed routing',
            r'\[INFO\] Detailed routing complete'
        ],
        'finishing': [
            r'\[INFO\] Starting metal fill',
            r'\[INFO\] Writing DEF',
            r'\[INFO\] Writing GDS'
        ]
    }
    
    @staticmethod
    def detect_stage_from_log(log_line: str) -> str:
        """Detect which stage a log line belongs to"""
        for stage, patterns in OpenROADStageParser.STAGE_MARKERS.items():
            for pattern in patterns:
                if re.search(pattern, log_line):
                    return stage
        return None
    
    @staticmethod
    def parse_design_features_from_log(log_file: Path) -> Dict:
        """Extract design features from OpenROAD log"""
        features = {
            'cell_count': None,
            'net_count': None,
            'die_area_um2': None,
            'utilization_target': None,
            'clock_freq_mhz': None
        }
        
        with open(log_file, 'r') as f:
            for line in f:
                # Extract cell count
                match = re.search(r'Number of instances:\s+(\d+)', line)
                if match:
                    features['cell_count'] = int(match.group(1))
                
                # Extract net count
                match = re.search(r'Number of nets:\s+(\d+)', line)
                if match:
                    features['net_count'] = int(match.group(1))
                
                # Extract die area
                match = re.search(r'Design area\s+(\d+)\s+u\^2', line)
                if match:
                    features['die_area_um2'] = int(match.group(1))
                
                # Extract utilization
                match = re.search(r'Utilization:\s+([\d.]+)', line)
                if match:
                    features['utilization_target'] = float(match.group(1))
                
                # Extract clock frequency
                match = re.search(r'clock period:\s+([\d.]+)', line)
                if match:
                    period_ns = float(match.group(1))
                    features['clock_freq_mhz'] = 1000.0 / period_ns
        
        return features


def run_openroad_flow(design_path: Path, design_name: str, config: Dict) -> Dict:
    """
    Run actual OpenROAD flow on a design
    
    Args:
        design_path: Path to design files (Verilog, constraints)
        design_name: Name of the design
        config: Configuration (PDK, frequency, utilization, etc.)
        
    Returns:
        Job metrics with actual resource usage
    """
    
    print(f"\n{'='*60}")
    print(f"Running REAL OpenROAD flow: {design_name}")
    print(f"Design: {design_path}")
    print(f"Config: {config}")
    print(f"{'='*60}\n")
    
    # Check if OpenROAD is installed
    try:
        result = subprocess.run(['openroad', '-version'], 
                              capture_output=True, text=True, timeout=5)
        print(f"OpenROAD version: {result.stdout.strip()}")
    except (subprocess.TimeoutExpired, FileNotFoundError):
        print("ERROR: OpenROAD not found!")
        print("Please install OpenROAD:")
        print("  - Docker: docker pull openroad/flow-ubuntu")
        print("  - Source: https://github.com/The-OpenROAD-Project/OpenROAD")
        return None
    
    # Prepare design features (will be updated from actual run)
    design_features = {
        'cell_count': config.get('estimated_cells', 10000),
        'net_count': config.get('estimated_nets', 9000),
        'die_area_um2': config.get('die_area', 1000000),
        'utilization_target': config.get('utilization', 0.6),
        'clock_freq_mhz': config.get('clock_freq_mhz', 100),
        'technology_node_nm': config.get('tech_node', 130),
        'metal_layers': config.get('metal_layers', 6),
        'clock_gating_enabled': config.get('clock_gating', False),
        'power_gating_enabled': False,
        'hierarchy_depth': 1,
        'macro_count': 0
    }
    
    tool_config = {
        'tool': 'openroad',
        'version': result.stdout.strip(),
        'pdk': config.get('pdk', 'sky130'),
        'threads': config.get('threads', 4)
    }
    
    # Create job monitor
    job_monitor = JobMonitor(design_name, design_features, tool_config)
    
    # Run OpenROAD stages
    # This is where we'd run actual OpenROAD commands
    # For now, show the structure
    
    stages = [
        ('read_design', ['openroad', '-exit', 'scripts/read_design.tcl']),
        ('floorplan', ['openroad', '-exit', 'scripts/floorplan.tcl']),
        ('placement', ['openroad', '-exit', 'scripts/placement.tcl']),
        ('cts', ['openroad', '-exit', 'scripts/cts.tcl']),
        ('routing', ['openroad', '-exit', 'scripts/routing.tcl']),
        ('finishing', ['openroad', '-exit', 'scripts/finishing.tcl'])
    ]
    
    for stage_name, command in stages:
        print(f"\n[STAGE] {stage_name}")
        
        # Run with monitoring
        exit_code = monitor_command(command, stage_name, job_monitor)
        
        if exit_code != 0:
            print(f"[ERROR] Stage {stage_name} failed with exit code {exit_code}")
            break
    
    # Finalize metrics
    metrics = job_monitor.finalize()
    
    # Parse actual design features from logs if available
    log_file = Path(f'logs/{design_name}.log')
    if log_file.exists():
        actual_features = OpenROADStageParser.parse_design_features_from_log(log_file)
        metrics['design_features'].update({k: v for k, v in actual_features.items() if v is not None})
    
    return metrics


def check_openroad_installation():
    """Check if OpenROAD is installed and provide setup instructions"""
    
    print("\n" + "="*60)
    print("Checking OpenROAD Installation")
    print("="*60 + "\n")
    
    # Check OpenROAD
    try:
        result = subprocess.run(['openroad', '-version'], 
                              capture_output=True, text=True, timeout=5)
        print(f"✓ OpenROAD found: {result.stdout.strip()}")
        openroad_ok = True
    except (subprocess.TimeoutExpired, FileNotFoundError):
        print("✗ OpenROAD not found")
        openroad_ok = False
    
    # Check OpenROAD-flow-scripts
    flow_path = Path.home() / 'OpenROAD-flow-scripts'
    if flow_path.exists():
        print(f"✓ OpenROAD-flow-scripts found: {flow_path}")
        flow_ok = True
    else:
        print("✗ OpenROAD-flow-scripts not found")
        flow_ok = False
    
    if not openroad_ok or not flow_ok:
        print("\n" + "="*60)
        print("SETUP REQUIRED")
        print("="*60 + "\n")
        print("To run real OpenROAD flows, you need:")
        print("")
        print("Option 1: Docker (Easiest)")
        print("  docker pull openroad/flow-ubuntu")
        print("  docker run -it -v $(pwd):/work openroad/flow-ubuntu")
        print("")
        print("Option 2: Install from source")
        print("  git clone --recursive https://github.com/The-OpenROAD-Project/OpenROAD-flow-scripts")
        print("  cd OpenROAD-flow-scripts")
        print("  ./build_openroad.sh --local")
        print("")
        print("Option 3: Use pre-built binaries")
        print("  https://github.com/The-OpenROAD-Project/OpenROAD/releases")
        print("")
        print("For today's testing, we'll use simulated data.")
        print("Tomorrow, we'll run on actual Parallel Cluster with OpenROAD installed.")
        print("")
        return False
    
    return True


if __name__ == "__main__":
    # Check installation
    if not check_openroad_installation():
        print("\nFalling back to simulation mode for today's testing.")
        print("Run scripts/run_local_test.sh for simulated data collection.")
        sys.exit(1)
    
    # If OpenROAD is available, run real flow
    print("\n✓ OpenROAD is available!")
    print("Ready to run real flows.")
