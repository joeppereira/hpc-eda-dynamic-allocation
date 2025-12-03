#!/usr/bin/env python3
"""
Import metrics from JSON files into database
"""

import json
from pathlib import Path
from datetime import datetime
from typing import Dict
from schema import (
    init_database, get_session,
    Job, DesignFeatures, ToolConfig, JobStage, StageResources
)


def import_job_metrics(metrics_file: Path, session):
    """Import job metrics from JSON file into database"""
    
    with open(metrics_file, 'r') as f:
        data = json.load(f)
    
    # Create Job record
    job = Job(
        job_name=data['job_name'],
        submit_time=datetime.fromisoformat(data['submit_time']),
        end_time=datetime.fromisoformat(data['end_time']),
        total_duration_sec=data['total_duration_sec'],
        workload_type='EDA',
        tool_name=data.get('tool_config', {}).get('tool', 'openroad')
    )
    session.add(job)
    session.flush()  # Get job.id
    
    # Create DesignFeatures
    df = data['design_features']
    design_features = DesignFeatures(
        job_id=job.id,
        cell_count=df.get('cell_count'),
        net_count=df.get('net_count'),
        die_area_um2=df.get('die_area_um2'),
        utilization_target=df.get('utilization_target'),
        aspect_ratio=df.get('aspect_ratio', 1.0),
        clock_freq_mhz=df.get('clock_freq_mhz'),
        clock_domains=df.get('clock_domains', 1),
        technology_node_nm=df.get('technology_node_nm', 130),
        metal_layers=df.get('metal_layers', 6),
        pdk=df.get('pdk', 'sky130'),
        clock_gating_enabled=int(df.get('clock_gating_enabled', False)),
        power_gating_enabled=int(df.get('power_gating_enabled', False)),
        hierarchy_depth=df.get('hierarchy_depth', 1),
        macro_count=df.get('macro_count', 0)
    )
    session.add(design_features)
    
    # Create ToolConfig
    tc = data.get('tool_config', {})
    tool_config = ToolConfig(
        job_id=job.id,
        tool_name=tc.get('tool', 'openroad'),
        tool_version=tc.get('version', 'unknown'),
        config_json=tc
    )
    session.add(tool_config)
    
    # Create JobStages and StageResources
    for idx, stage_data in enumerate(data.get('stages', [])):
        stage = JobStage(
            job_id=job.id,
            stage_name=stage_data['stage_name'],
            stage_order=idx + 1,
            start_time=datetime.fromisoformat(stage_data['start_time']),
            end_time=datetime.fromisoformat(stage_data['end_time']),
            duration_sec=stage_data['duration_sec']
        )
        session.add(stage)
        session.flush()  # Get stage.id
        
        # Resources
        res = stage_data.get('resources', {})
        resources = StageResources(
            stage_id=stage.id,
            cpu_util_avg=res.get('cpu_util_avg'),
            cpu_util_peak=res.get('cpu_util_peak'),
            memory_avg_gb=res.get('memory_avg_gb'),
            memory_peak_gb=res.get('memory_peak_gb'),
            disk_read_gb=res.get('disk_read_gb'),
            disk_write_gb=res.get('disk_write_gb'),
            bottleneck_type=stage_data.get('bottleneck', {}).get('type'),
            bottleneck_severity=stage_data.get('bottleneck', {}).get('severity')
        )
        session.add(resources)
    
    session.commit()
    print(f"Imported job: {data['job_name']} with {len(data.get('stages', []))} stages")
    return job.id


def import_all_metrics(metrics_dir: Path, db_path: str = 'sqlite:///data/metrics.db'):
    """Import all JSON metrics files from directory"""
    
    engine = init_database(db_path)
    session = get_session(engine)
    
    metrics_files = list(metrics_dir.glob('*.json'))
    print(f"Found {len(metrics_files)} metrics files")
    
    imported_count = 0
    for metrics_file in metrics_files:
        try:
            import_job_metrics(metrics_file, session)
            imported_count += 1
        except Exception as e:
            print(f"Error importing {metrics_file}: {e}")
            session.rollback()
    
    print(f"\nSuccessfully imported {imported_count}/{len(metrics_files)} jobs")
    session.close()


if __name__ == "__main__":
    import sys
    
    if len(sys.argv) > 1:
        metrics_dir = Path(sys.argv[1])
    else:
        metrics_dir = Path('data/metrics')
    
    if not metrics_dir.exists():
        print(f"Metrics directory not found: {metrics_dir}")
        sys.exit(1)
    
    import_all_metrics(metrics_dir)
