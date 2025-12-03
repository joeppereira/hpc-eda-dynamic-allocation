#!/usr/bin/env python3
"""
OpenROAD execution wrapper with monitoring
Runs OpenROAD in Docker and monitors resources + parses logs
"""

import sys
import os
import subprocess
import threading
import time
import json
from pathlib import Path
from datetime import datetime

sys.path.append(str(Path(__file__).parent.parent))

from monitoring.resource_monitor import JobMonitor
from monitoring.openroad_log_parser import OpenROADLogParser


class OpenROADRunner:
    """Run OpenROAD with monitoring and log parsing"""
    
    def __init__(self, job_name: str, design_features: dict, tool_config: dict):
        self.job_name = job_name
        self.design_features = design_features
        self.tool_config = tool_config
        self.log_file = Path(f"data/temp/{job_name}.log")
        self.metrics_file = Path(f"data/metrics/{job_name}.json")
        
        # Create directories
        self.log_file.parent.mkdir(parents=True, exist_ok=True)
        self.metrics_file.parent.mkdir(parents=True, exist_ok=True)
        
        # Initialize components
        self.job_monitor = JobMonitor(job_name, design_features, tool_config)
        self.log_parser = OpenROADLogParser()
        self.process = None
        self.log_thread = None
        self.monitoring_active = False
    
    def run_openroad(self, script_path: str, design_path: str = None) -> int:
        """
        Run OpenROAD with monitoring
        
        Args:
            script_path: Path to OpenROAD TCL script
            design_path: Optional path to design files
            
        Returns:
            Exit code
        """
        print(f"[RUNNER] Starting OpenROAD job: {self.job_name}")
        print(f"[RUNNER] Script: {script_path}")
        print(f"[RUNNER] Log file: {self.log_file}")
        
        # Build Docker command
        docker_cmd = self._build_docker_command(script_path, design_path)
        
        # Open log file
        with open(self.log_file, 'w') as log_fp:
            # Start OpenROAD process
            self.process = subprocess.Popen(
                docker_cmd,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                bufsize=1
            )
            
            # Start monitoring
            self.monitoring_active = True
            self.job_monitor.start_stage('openroad_execution', self.process)
            
            # Start log parsing thread
            self.log_thread = threading.Thread(
                target=self._parse_log_stream,
                args=(self.process.stdout, log_fp)
            )
            self.log_thread.start()
            
            # Monitor resources while process runs
            while self.process.poll() is None:
                self.job_monitor.monitor_loop()
                time.sleep(1.0)
            
            # Stop monitoring
            self.monitoring_active = False
            
            # Wait for log thread to finish
            if self.log_thread:
                self.log_thread.join(timeout=5.0)
            
            exit_code = self.process.returncode
            print(f"[RUNNER] OpenROAD completed with exit code: {exit_code}")
            
            return exit_code
    
    def _build_docker_command(self, script_path: str, design_path: str = None) -> list:
        """Build Docker command for OpenROAD"""
        
        # Get absolute paths
        script_abs = Path(script_path).resolve()
        work_dir = script_abs.parent
        
        cmd = [
            'docker', 'run',
            '--rm',
            '-v', f'{work_dir}:/work',
            'openroad/flow-ubuntu',
            'openroad',
            f'/work/{script_abs.name}'
        ]
        
        return cmd
    
    def _parse_log_stream(self, stdout, log_fp):
        """Parse log stream in real-time"""
        for line in stdout:
            # Write to log file
            log_fp.write(line)
            log_fp.flush()
            
            # Parse line for stage detection
            self.log_parser.parse_line(line)
            
            # Update current stage in monitor
            if self.log_parser.current_stage:
                stage_name = self.log_parser.current_stage.value
                # Check if we need to transition stages
                if (not hasattr(self, '_last_stage') or 
                    self._last_stage != stage_name):
                    print(f"[RUNNER] Stage detected: {stage_name}")
                    self._last_stage = stage_name
    
    def save_metrics(self):
        """Save combined metrics to JSON"""
        print(f"[RUNNER] Saving metrics to {self.metrics_file}")
        
        # Get monitoring metrics
        job_metrics = self.job_monitor.finalize()
        
        # Get log parsing results
        log_results = self.log_parser.get_results()
        stage_durations = self.log_parser.get_stage_durations()
        
        # Merge design features from log if available
        extracted_features = log_results['design_features']
        for key, value in extracted_features.items():
            if value is not None and key not in self.design_features:
                self.design_features[key] = value
        
        # Combine metrics
        combined = {
            'job_name': self.job_name,
            'submit_time': job_metrics['submit_time'],
            'end_time': job_metrics['end_time'],
            'total_duration_sec': job_metrics['total_duration_sec'],
            'design_features': self.design_features,
            'tool_config': self.tool_config,
            'stages': [],
            'log_parsing': {
                'stages_detected': log_results['total_stages_detected'],
                'events_detected': log_results['total_events'],
                'stage_durations': stage_durations
            }
        }
        
        # Add stage metrics
        # For now, use the overall metrics as a single stage
        # In production, we'd correlate with actual stage boundaries
        if job_metrics['stages']:
            combined['stages'] = job_metrics['stages']
        
        # Save to file
        with open(self.metrics_file, 'w') as f:
            json.dump(combined, f, indent=2)
        
        print(f"[RUNNER] Metrics saved successfully")
        
        return combined


def main():
    """Main entry point"""
    import argparse
    
    parser = argparse.ArgumentParser(description='Run OpenROAD with monitoring')
    parser.add_argument('--name', required=True, help='Job name')
    parser.add_argument('--script', required=True, help='OpenROAD TCL script')
    parser.add_argument('--design', help='Design directory')
    parser.add_argument('--cells', type=int, default=5000, help='Cell count')
    parser.add_argument('--freq', type=int, default=100, help='Frequency (MHz)')
    parser.add_argument('--util', type=float, default=0.6, help='Utilization')
    
    args = parser.parse_args()
    
    # Design features
    design_features = {
        'cell_count': args.cells,
        'net_count': int(args.cells * 0.9),
        'die_area_um2': args.cells * 200,
        'utilization_target': args.util,
        'clock_freq_mhz': args.freq,
        'technology_node_nm': 130,
        'metal_layers': 6,
        'clock_gating_enabled': False,
        'power_gating_enabled': False,
        'hierarchy_depth': 3,
        'macro_count': 0
    }
    
    # Tool config
    tool_config = {
        'tool': 'openroad',
        'threads': 4,
        'version': 'docker'
    }
    
    # Run OpenROAD
    runner = OpenROADRunner(args.name, design_features, tool_config)
    
    try:
        exit_code = runner.run_openroad(args.script, args.design)
        
        if exit_code == 0:
            runner.save_metrics()
            print(f"\n✓ Job completed successfully")
            print(f"✓ Metrics: {runner.metrics_file}")
            print(f"✓ Log: {runner.log_file}")
        else:
            print(f"\n✗ Job failed with exit code {exit_code}")
            print(f"✗ Check log: {runner.log_file}")
            sys.exit(exit_code)
    
    except KeyboardInterrupt:
        print("\n[RUNNER] Interrupted by user")
        if runner.process:
            runner.process.terminate()
        sys.exit(1)
    
    except Exception as e:
        print(f"\n✗ Error: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)


if __name__ == "__main__":
    main()
