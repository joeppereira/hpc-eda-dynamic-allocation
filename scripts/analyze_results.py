#!/usr/bin/env python3
"""
Analyze collected metrics and generate report
"""

import json
import pandas as pd
from pathlib import Path
import matplotlib.pyplot as plt
import seaborn as sns

sns.set_style('whitegrid')


def load_all_metrics(metrics_dir: Path) -> pd.DataFrame:
    """Load all metrics files into DataFrame"""
    
    data = []
    for metrics_file in metrics_dir.glob('*.json'):
        with open(metrics_file, 'r') as f:
            job_data = json.load(f)
        
        for stage in job_data.get('stages', []):
            row = {
                'job_name': job_data['job_name'],
                'stage_name': stage['stage_name'],
                'duration_sec': stage['duration_sec'],
                'cpu_util_avg': stage['resources']['cpu_util_avg'],
                'cpu_util_peak': stage['resources']['cpu_util_peak'],
                'memory_peak_gb': stage['resources']['memory_peak_gb'],
                'memory_avg_gb': stage['resources']['memory_avg_gb'],
                'disk_read_gb': stage['resources']['disk_read_gb'],
                'disk_write_gb': stage['resources']['disk_write_gb'],
                'bottleneck_type': stage['bottleneck']['type'],
                'bottleneck_severity': stage['bottleneck']['severity'],
                # Design features
                'cell_count': job_data['design_features']['cell_count'],
                'clock_freq_mhz': job_data['design_features']['clock_freq_mhz'],
                'utilization': job_data['design_features']['utilization_target']
            }
            data.append(row)
    
    return pd.DataFrame(data)


def generate_report(df: pd.DataFrame):
    """Generate analysis report"""
    
    print("\n" + "="*60)
    print("RESOURCE USAGE ANALYSIS")
    print("="*60 + "\n")
    
    # Summary statistics
    print("Summary Statistics:")
    print(f"  Total jobs: {df['job_name'].nunique()}")
    print(f"  Total stages: {len(df)}")
    print(f"  Stages: {', '.join(df['stage_name'].unique())}")
    print()
    
    # Per-stage analysis
    print("Per-Stage Resource Usage:")
    print("-" * 60)
    for stage in df['stage_name'].unique():
        stage_data = df[df['stage_name'] == stage]
        print(f"\n{stage}:")
        print(f"  Avg duration:    {stage_data['duration_sec'].mean():.1f} sec")
        print(f"  Avg CPU util:    {stage_data['cpu_util_avg'].mean():.1f}%")
        print(f"  Peak memory:     {stage_data['memory_peak_gb'].mean():.2f} GB")
        print(f"  Avg I/O read:    {stage_data['disk_read_gb'].mean():.3f} GB")
        print(f"  Avg I/O write:   {stage_data['disk_write_gb'].mean():.3f} GB")
        print(f"  Primary bottleneck: {stage_data['bottleneck_type'].mode()[0]}")
    
    # Scaling analysis
    print("\n" + "="*60)
    print("SCALING ANALYSIS")
    print("="*60 + "\n")
    
    for stage in df['stage_name'].unique():
        stage_data = df[df['stage_name'] == stage]
        
        # Correlation with cell count
        corr_duration = stage_data[['cell_count', 'duration_sec']].corr().iloc[0, 1]
        corr_memory = stage_data[['cell_count', 'memory_peak_gb']].corr().iloc[0, 1]
        
        print(f"{stage}:")
        print(f"  Cell count vs Duration correlation: {corr_duration:.3f}")
        print(f"  Cell count vs Memory correlation:   {corr_memory:.3f}")
    
    # Bottleneck distribution
    print("\n" + "="*60)
    print("BOTTLENECK DISTRIBUTION")
    print("="*60 + "\n")
    
    bottleneck_counts = df.groupby(['stage_name', 'bottleneck_type']).size().unstack(fill_value=0)
    print(bottleneck_counts)
    
    print("\n" + "="*60)
    print("✓ Analysis complete!")
    print("="*60 + "\n")


def plot_results(df: pd.DataFrame, output_dir: Path):
    """Generate visualization plots"""
    
    output_dir.mkdir(parents=True, exist_ok=True)
    
    # Plot 1: Duration by stage and cell count
    fig, axes = plt.subplots(1, 3, figsize=(15, 5))
    
    for idx, stage in enumerate(df['stage_name'].unique()):
        stage_data = df[df['stage_name'] == stage]
        axes[idx].scatter(stage_data['cell_count'], stage_data['duration_sec'], alpha=0.6)
        axes[idx].set_xlabel('Cell Count')
        axes[idx].set_ylabel('Duration (sec)')
        axes[idx].set_title(f'{stage}')
        axes[idx].grid(True, alpha=0.3)
    
    plt.tight_layout()
    plt.savefig(output_dir / 'duration_vs_cells.png', dpi=150)
    print(f"Saved: {output_dir / 'duration_vs_cells.png'}")
    
    # Plot 2: Memory usage by stage
    fig, ax = plt.subplots(figsize=(10, 6))
    df.boxplot(column='memory_peak_gb', by='stage_name', ax=ax)
    ax.set_xlabel('Stage')
    ax.set_ylabel('Peak Memory (GB)')
    ax.set_title('Memory Usage by Stage')
    plt.suptitle('')  # Remove default title
    plt.tight_layout()
    plt.savefig(output_dir / 'memory_by_stage.png', dpi=150)
    print(f"Saved: {output_dir / 'memory_by_stage.png'}")
    
    # Plot 3: CPU utilization
    fig, ax = plt.subplots(figsize=(10, 6))
    df.boxplot(column='cpu_util_avg', by='stage_name', ax=ax)
    ax.set_xlabel('Stage')
    ax.set_ylabel('CPU Utilization (%)')
    ax.set_title('CPU Utilization by Stage')
    plt.suptitle('')
    plt.tight_layout()
    plt.savefig(output_dir / 'cpu_by_stage.png', dpi=150)
    print(f"Saved: {output_dir / 'cpu_by_stage.png'}")
    
    plt.close('all')


def main():
    metrics_dir = Path('data/metrics')
    
    if not metrics_dir.exists() or not list(metrics_dir.glob('*.json')):
        print("No metrics found. Run jobs first.")
        return
    
    print("Loading metrics...")
    df = load_all_metrics(metrics_dir)
    
    print(f"Loaded {len(df)} stage records from {df['job_name'].nunique()} jobs")
    
    # Generate report
    generate_report(df)
    
    # Generate plots
    print("\nGenerating visualizations...")
    plot_results(df, Path('data/results'))
    
    print("\n✓ Results analysis complete!")
    print("  View plots in: data/results/")


if __name__ == "__main__":
    main()
