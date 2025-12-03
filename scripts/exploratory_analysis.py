#!/usr/bin/env python3
"""
Exploratory Data Analysis of collected job metrics
Analyzes resource scaling, correlations, and data quality
"""

import sys
sys.path.append('.')

import pandas as pd
import numpy as np
import matplotlib.pyplot as plt
import seaborn as sns
from pathlib import Path
from database.schema import init_database, get_session, Job, DesignFeatures, JobStage, StageResources

# Set style
sns.set_style("whitegrid")
plt.rcParams['figure.figsize'] = (12, 8)


def load_data_from_db(db_path: str = 'sqlite:///data/metrics.db') -> pd.DataFrame:
    """Load all job data from database into DataFrame"""
    engine = init_database(db_path)
    session = get_session(engine)
    
    data = []
    
    jobs = session.query(Job).all()
    print(f"Loading {len(jobs)} jobs from database...")
    
    for job in jobs:
        if not job.design_features or not job.stages:
            continue
        
        df = job.design_features
        
        for stage in job.stages:
            if not stage.resources:
                continue
            
            res = stage.resources
            
            row = {
                # Job info
                'job_name': job.job_name,
                'job_id': job.id,
                
                # Design features
                'cell_count': df.cell_count,
                'net_count': df.net_count,
                'die_area_um2': df.die_area_um2,
                'utilization_target': df.utilization_target,
                'aspect_ratio': df.aspect_ratio,
                'clock_freq_mhz': df.clock_freq_mhz,
                'clock_domains': df.clock_domains,
                'technology_node_nm': df.technology_node_nm,
                'metal_layers': df.metal_layers,
                'hierarchy_depth': df.hierarchy_depth,
                
                # Stage info
                'stage_name': stage.stage_name,
                'stage_order': stage.stage_order,
                'duration_sec': stage.duration_sec,
                
                # Resources
                'cpu_util_avg': res.cpu_util_avg,
                'cpu_util_peak': res.cpu_util_peak,
                'memory_peak_gb': res.memory_peak_gb,
                'memory_avg_gb': res.memory_avg_gb,
                'disk_read_gb': res.disk_read_gb,
                'disk_write_gb': res.disk_write_gb,
                'bottleneck_type': res.bottleneck_type,
            }
            
            data.append(row)
    
    df = pd.DataFrame(data)
    print(f"Loaded {len(df)} stage records")
    return df


def basic_statistics(df: pd.DataFrame):
    """Print basic statistics"""
    print("\n" + "="*80)
    print("BASIC STATISTICS")
    print("="*80)
    
    print(f"\nTotal jobs: {df['job_id'].nunique()}")
    print(f"Total stage records: {len(df)}")
    print(f"Stages: {df['stage_name'].unique()}")
    
    print("\n--- Design Features ---")
    print(df[['cell_count', 'net_count', 'die_area_um2', 'utilization_target', 'clock_freq_mhz']].describe())
    
    print("\n--- Resource Usage by Stage ---")
    for stage in df['stage_name'].unique():
        stage_df = df[df['stage_name'] == stage]
        print(f"\n{stage.upper()}:")
        print(f"  CPU avg: {stage_df['cpu_util_avg'].mean():.1f}% (peak: {stage_df['cpu_util_peak'].mean():.1f}%)")
        print(f"  Memory peak: {stage_df['memory_peak_gb'].mean():.2f} GB")
        print(f"  Duration: {stage_df['duration_sec'].mean():.1f} sec")
        print(f"  Bottleneck: {stage_df['bottleneck_type'].mode()[0] if len(stage_df) > 0 else 'N/A'}")


def analyze_correlations(df: pd.DataFrame):
    """Analyze correlations between design features and resources"""
    print("\n" + "="*80)
    print("CORRELATION ANALYSIS")
    print("="*80)
    
    # Select numeric columns
    feature_cols = ['cell_count', 'net_count', 'die_area_um2', 'utilization_target', 'clock_freq_mhz']
    resource_cols = ['cpu_util_avg', 'memory_peak_gb', 'duration_sec']
    
    for stage in df['stage_name'].unique():
        stage_df = df[df['stage_name'] == stage]
        
        print(f"\n--- {stage.upper()} Stage ---")
        
        for resource in resource_cols:
            print(f"\n{resource}:")
            corr = stage_df[feature_cols + [resource]].corr()[resource].drop(resource).sort_values(ascending=False)
            for feat, val in corr.items():
                print(f"  {feat:25s}: {val:+.3f}")


def plot_resource_scaling(df: pd.DataFrame, output_dir: Path):
    """Plot how resources scale with design size"""
    output_dir.mkdir(parents=True, exist_ok=True)
    
    print("\n" + "="*80)
    print("GENERATING PLOTS")
    print("="*80)
    
    stages = df['stage_name'].unique()
    
    # Memory vs Cell Count
    fig, axes = plt.subplots(1, len(stages), figsize=(15, 5))
    if len(stages) == 1:
        axes = [axes]
    
    for idx, stage in enumerate(stages):
        stage_df = df[df['stage_name'] == stage]
        axes[idx].scatter(stage_df['cell_count'], stage_df['memory_peak_gb'], alpha=0.6)
        axes[idx].set_xlabel('Cell Count')
        axes[idx].set_ylabel('Memory Peak (GB)')
        axes[idx].set_title(f'{stage.capitalize()} Stage')
        axes[idx].grid(True, alpha=0.3)
    
    plt.tight_layout()
    plt.savefig(output_dir / 'memory_vs_cell_count.png', dpi=150)
    print(f"Saved: {output_dir / 'memory_vs_cell_count.png'}")
    plt.close()
    
    # Duration vs Frequency
    fig, axes = plt.subplots(1, len(stages), figsize=(15, 5))
    if len(stages) == 1:
        axes = [axes]
    
    for idx, stage in enumerate(stages):
        stage_df = df[df['stage_name'] == stage]
        axes[idx].scatter(stage_df['clock_freq_mhz'], stage_df['duration_sec'], alpha=0.6)
        axes[idx].set_xlabel('Clock Frequency (MHz)')
        axes[idx].set_ylabel('Duration (sec)')
        axes[idx].set_title(f'{stage.capitalize()} Stage')
        axes[idx].grid(True, alpha=0.3)
    
    plt.tight_layout()
    plt.savefig(output_dir / 'duration_vs_frequency.png', dpi=150)
    print(f"Saved: {output_dir / 'duration_vs_frequency.png'}")
    plt.close()
    
    # Resource distribution by stage
    fig, axes = plt.subplots(2, 2, figsize=(12, 10))
    
    # CPU utilization
    df.boxplot(column='cpu_util_avg', by='stage_name', ax=axes[0, 0])
    axes[0, 0].set_title('CPU Utilization by Stage')
    axes[0, 0].set_ylabel('CPU Avg (%)')
    
    # Memory
    df.boxplot(column='memory_peak_gb', by='stage_name', ax=axes[0, 1])
    axes[0, 1].set_title('Memory Usage by Stage')
    axes[0, 1].set_ylabel('Memory Peak (GB)')
    
    # Duration
    df.boxplot(column='duration_sec', by='stage_name', ax=axes[1, 0])
    axes[1, 0].set_title('Duration by Stage')
    axes[1, 0].set_ylabel('Duration (sec)')
    
    # Bottleneck distribution
    bottleneck_counts = df.groupby(['stage_name', 'bottleneck_type']).size().unstack(fill_value=0)
    bottleneck_counts.plot(kind='bar', stacked=True, ax=axes[1, 1])
    axes[1, 1].set_title('Bottleneck Distribution by Stage')
    axes[1, 1].set_ylabel('Count')
    axes[1, 1].legend(title='Bottleneck Type')
    
    plt.suptitle('')  # Remove default title
    plt.tight_layout()
    plt.savefig(output_dir / 'resource_distributions.png', dpi=150)
    print(f"Saved: {output_dir / 'resource_distributions.png'}")
    plt.close()


def check_data_quality(df: pd.DataFrame):
    """Check for data quality issues"""
    print("\n" + "="*80)
    print("DATA QUALITY CHECKS")
    print("="*80)
    
    # Check for missing values
    print("\nMissing values:")
    missing = df.isnull().sum()
    if missing.sum() == 0:
        print("  ✓ No missing values")
    else:
        print(missing[missing > 0])
    
    # Check for outliers
    print("\nOutlier detection (values > 3 std from mean):")
    numeric_cols = ['cpu_util_avg', 'memory_peak_gb', 'duration_sec']
    
    for col in numeric_cols:
        mean = df[col].mean()
        std = df[col].std()
        outliers = df[(df[col] > mean + 3*std) | (df[col] < mean - 3*std)]
        if len(outliers) > 0:
            print(f"  ⚠ {col}: {len(outliers)} outliers")
        else:
            print(f"  ✓ {col}: No outliers")
    
    # Check realistic bounds
    print("\nRealistic bounds check:")
    checks = [
        ('CPU utilization', df['cpu_util_avg'].between(0, 100).all()),
        ('Memory positive', (df['memory_peak_gb'] > 0).all()),
        ('Duration positive', (df['duration_sec'] > 0).all()),
    ]
    
    for check_name, passed in checks:
        status = "✓" if passed else "✗"
        print(f"  {status} {check_name}")


def identify_patterns(df: pd.DataFrame):
    """Identify interesting patterns in the data"""
    print("\n" + "="*80)
    print("PATTERN IDENTIFICATION")
    print("="*80)
    
    # Which stage uses most resources?
    print("\n--- Resource-Intensive Stages ---")
    for metric in ['memory_peak_gb', 'duration_sec']:
        stage_avg = df.groupby('stage_name')[metric].mean().sort_values(ascending=False)
        print(f"\n{metric}:")
        for stage, value in stage_avg.items():
            print(f"  {stage:15s}: {value:.2f}")
    
    # How does utilization affect resources?
    print("\n--- Utilization Impact ---")
    util_groups = df.groupby('utilization_target')[['memory_peak_gb', 'duration_sec']].mean()
    print(util_groups)
    
    # Frequency impact
    print("\n--- Frequency Impact ---")
    freq_groups = df.groupby('clock_freq_mhz')[['memory_peak_gb', 'duration_sec']].mean()
    print(freq_groups)


def main():
    """Run complete exploratory analysis"""
    print("="*80)
    print("EXPLORATORY DATA ANALYSIS")
    print("="*80)
    
    # Load data
    df = load_data_from_db()
    
    if len(df) == 0:
        print("ERROR: No data found in database")
        return
    
    # Run analyses
    basic_statistics(df)
    check_data_quality(df)
    analyze_correlations(df)
    identify_patterns(df)
    
    # Generate plots
    output_dir = Path('data/results')
    plot_resource_scaling(df, output_dir)
    
    print("\n" + "="*80)
    print("ANALYSIS COMPLETE")
    print("="*80)
    print(f"\nPlots saved to: {output_dir}")
    print("\nKey Findings:")
    print("  - Check correlation analysis for feature importance")
    print("  - Review plots for scaling relationships")
    print("  - Verify data quality checks passed")


if __name__ == "__main__":
    main()
