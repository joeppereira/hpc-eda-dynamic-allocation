#!/usr/bin/env python3
"""
Resource monitoring script - simulates SPANK plugin functionality for local testing.
Monitors CPU, memory, I/O for OpenROAD stages.
"""

import psutil
import time
import json
import os
import subprocess
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Optional


class StageMonitor:
    """Monitor resources for a specific job stage"""
    
    def __init__(self, stage_name: str, sampling_interval: float = 1.0):
        self.stage_name = stage_name
        self.sampling_interval = sampling_interval
        self.samples = []
        self.start_time = None
        self.end_time = None
        self.process = None
        
    def start(self, process: psutil.Process):
        """Start monitoring a process"""
        self.process = process
        self.start_time = time.time()
        
    def sample(self):
        """Collect a single resource sample"""
        if not self.process:
            return
            
        try:
            # Get process and children
            procs = [self.process] + self.process.children(recursive=True)
            
            # Aggregate metrics
            cpu_percent = sum(p.cpu_percent(interval=0.1) for p in procs if p.is_running())
            memory_info = sum(p.memory_info().rss for p in procs if p.is_running())
            
            # I/O counters (if available)
            try:
                io_counters = sum(
                    (p.io_counters().read_bytes, p.io_counters().write_bytes)
                    for p in procs if p.is_running()
                )
                disk_read, disk_write = io_counters[0], io_counters[1]
            except (AttributeError, psutil.AccessDenied):
                disk_read, disk_write = 0, 0
            
            sample = {
                'timestamp': time.time(),
                'cpu_percent': cpu_percent,
                'memory_rss_bytes': memory_info,
                'disk_read_bytes': disk_read,
                'disk_write_bytes': disk_write,
                'num_threads': sum(p.num_threads() for p in procs if p.is_running())
            }
            
            self.samples.append(sample)
            
        except (psutil.NoSuchProcess, psutil.AccessDenied):
            pass
    
    def stop(self):
        """Stop monitoring and compute summary"""
        self.end_time = time.time()
        
    def get_summary(self) -> Dict:
        """Compute summary statistics"""
        if not self.samples:
            return {}
        
        cpu_values = [s['cpu_percent'] for s in self.samples]
        memory_values = [s['memory_rss_bytes'] for s in self.samples]
        
        # Compute I/O deltas
        disk_read_total = 0
        disk_write_total = 0
        if len(self.samples) > 1:
            disk_read_total = self.samples[-1]['disk_read_bytes'] - self.samples[0]['disk_read_bytes']
            disk_write_total = self.samples[-1]['disk_write_bytes'] - self.samples[0]['disk_write_bytes']
        
        summary = {
            'stage_name': self.stage_name,
            'start_time': datetime.fromtimestamp(self.start_time).isoformat(),
            'end_time': datetime.fromtimestamp(self.end_time).isoformat(),
            'duration_sec': self.end_time - self.start_time,
            'resources': {
                'cpu_util_avg': sum(cpu_values) / len(cpu_values),
                'cpu_util_peak': max(cpu_values),
                'memory_peak_gb': max(memory_values) / (1024**3),
                'memory_avg_gb': sum(memory_values) / len(memory_values) / (1024**3),
                'disk_read_gb': disk_read_total / (1024**3),
                'disk_write_gb': disk_write_total / (1024**3),
            },
            'bottleneck': self._identify_bottleneck(cpu_values, memory_values)
        }
        
        return summary
    
    def _identify_bottleneck(self, cpu_values: List[float], memory_values: List[float]) -> Dict:
        """Identify primary bottleneck"""
        avg_cpu = sum(cpu_values) / len(cpu_values)
        peak_memory_gb = max(memory_values) / (1024**3)
        
        # Simple heuristics
        if avg_cpu > 80:
            return {'type': 'compute', 'severity': min(avg_cpu / 100, 1.0)}
        elif peak_memory_gb > 8:  # Arbitrary threshold
            return {'type': 'memory', 'severity': min(peak_memory_gb / 16, 1.0)}
        else:
            return {'type': 'io', 'severity': 0.3}


class JobMonitor:
    """Monitor an entire job with multiple stages"""
    
    def __init__(self, job_name: str, design_features: Dict, tool_config: Dict):
        self.job_name = job_name
        self.design_features = design_features
        self.tool_config = tool_config
        self.stages = []
        self.current_stage = None
        self.job_start_time = time.time()
        
    def start_stage(self, stage_name: str, process: psutil.Process):
        """Start monitoring a new stage"""
        if self.current_stage:
            self.current_stage.stop()
            self.stages.append(self.current_stage.get_summary())
        
        self.current_stage = StageMonitor(stage_name)
        self.current_stage.start(process)
        
    def monitor_loop(self):
        """Continuous monitoring loop"""
        if self.current_stage:
            self.current_stage.sample()
    
    def finalize(self) -> Dict:
        """Finalize monitoring and return complete job metrics"""
        if self.current_stage:
            self.current_stage.stop()
            self.stages.append(self.current_stage.get_summary())
        
        job_end_time = time.time()
        
        return {
            'job_name': self.job_name,
            'submit_time': datetime.fromtimestamp(self.job_start_time).isoformat(),
            'end_time': datetime.fromtimestamp(job_end_time).isoformat(),
            'total_duration_sec': job_end_time - self.job_start_time,
            'design_features': self.design_features,
            'tool_config': self.tool_config,
            'stages': self.stages
        }


def monitor_command(command: List[str], stage_name: str, job_monitor: JobMonitor) -> int:
    """
    Execute a command and monitor its resources
    
    Args:
        command: Command to execute
        stage_name: Name of the stage
        job_monitor: JobMonitor instance
        
    Returns:
        Exit code of the command
    """
    print(f"[MONITOR] Starting stage: {stage_name}")
    print(f"[MONITOR] Command: {' '.join(command)}")
    
    # Start process
    proc = subprocess.Popen(
        command,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True
    )
    
    # Get psutil process
    ps_proc = psutil.Process(proc.pid)
    
    # Start monitoring
    job_monitor.start_stage(stage_name, ps_proc)
    
    # Monitor while process runs
    while proc.poll() is None:
        job_monitor.monitor_loop()
        time.sleep(1.0)
    
    # Get output
    stdout, stderr = proc.communicate()
    
    print(f"[MONITOR] Stage {stage_name} completed with exit code {proc.returncode}")
    
    if proc.returncode != 0:
        print(f"[MONITOR] STDERR: {stderr}")
    
    return proc.returncode


def save_metrics(metrics: Dict, output_file: Path):
    """Save metrics to JSON file"""
    output_file.parent.mkdir(parents=True, exist_ok=True)
    
    with open(output_file, 'w') as f:
        json.dump(metrics, f, indent=2)
    
    print(f"[MONITOR] Metrics saved to {output_file}")


if __name__ == "__main__":
    # Example usage
    design_features = {
        'cell_count': 5000,
        'net_count': 4500,
        'die_area_um2': 100000,
        'utilization_target': 0.6,
        'clock_freq_mhz': 100
    }
    
    tool_config = {
        'tool': 'openroad',
        'threads': 4
    }
    
    monitor = JobMonitor('test_job', design_features, tool_config)
    
    # Simulate monitoring stages
    monitor_command(['sleep', '2'], 'synthesis', monitor)
    monitor_command(['sleep', '3'], 'placement', monitor)
    
    # Finalize and save
    metrics = monitor.finalize()
    save_metrics(metrics, Path('data/metrics/test_job.json'))
