#!/usr/bin/env python3
"""
Generate comprehensive resource demand table
Shows actual collected data and predicted resources for various design configurations
"""

import sys
sys.path.append('.')

import pandas as pd
import numpy as np
from database.schema import init_database, get_session, Job, DesignFeatures, JobStage, StageResources
from prediction.model import ResourcePredictor
from pathlib import Path

def load_actual_data():
    """Load actual collected data from database"""
    engine = init_database('sqlite:///data/metrics.db')
    session = get_session(engine)
    
    data = []
    jobs = session.query(Job).all()
    
    for job in jobs:
        if not job.design_features or not job.stages:
            continue
        
        df = job.design_features
        
        for stage in job.stages:
            if not stage.resources:
                continue
            
            res = stage.resources
            
            data.append({
                'job_name': job.job_name,
                'stage': stage.stage_name,
                'cell_count': df.cell_count,
                'freq_mhz': df.clock_freq_mhz,
                'utilization': df.utilization_target,
                'tech_node': df.technology_node_nm,
                'cpu_avg_%': res.cpu_util_avg,
                'cpu_peak_%': res.cpu_util_peak,
                'memory_gb': res.memory_peak_gb,
                'duration_sec': stage.duration_sec,
                'source': 'ACTUAL'
            })
    
    return pd.DataFrame(data)

def generate_predictions():
    """Generate predictions for various design configurations"""
    
    # Load trained model
    try:
        predictor = ResourcePredictor.load(Path('prediction/trained_model.pkl'))
    except:
        print("Model not found. Training new model...")
        from prediction.train_model import load_training_data
        data = load_training_data()
        predictor = ResourcePredictor()
        predictor.train(data, alpha=1.0)
        predictor.save(Path('prediction/trained_model.pkl'))
    
    # Design variations to predict
    variations = [
        # Small designs
        {'name': 'tiny', 'cells': 1000, 'freq': 100, 'util': 0.5},
        {'name': 'tiny', 'cells': 1000, 'freq': 500, 'util': 0.7},
        
        # Small designs (current data)
        {'name': 'small', 'cells': 5000, 'freq': 100, 'util': 0.5},
        {'name': 'small', 'cells': 5000, 'freq': 200, 'util': 0.6},
        {'name': 'small', 'cells': 5000, 'freq': 500, 'util': 0.7},
        
        # Medium designs (current data)
        {'name': 'medium', 'cells': 20000, 'freq': 100, 'util': 0.6},
        {'name': 'medium', 'cells': 20000, 'freq': 200, 'util': 0.7},
        
        # Large designs (current data)
        {'name': 'large', 'cells': 50000, 'freq': 100, 'util': 0.6},
        {'name': 'large', 'cells': 50000, 'freq': 200, 'util': 0.7},
        
        # Extra large (predictions only)
        {'name': 'xlarge', 'cells': 100000, 'freq': 200, 'util': 0.6},
        {'name': 'xlarge', 'cells': 100000, 'freq': 500, 'util': 0.7},
        
        # Huge (predictions only)
        {'name': 'huge', 'cells': 500000, 'freq': 500, 'util': 0.7},
        {'name': 'huge', 'cells': 500000, 'freq': 1000, 'util': 0.7},
        
        # Massive (predictions only)
        {'name': 'massive', 'cells': 1000000, 'freq': 500, 'util': 0.7},
        {'name': 'massive', 'cells': 1000000, 'freq': 1000, 'util': 0.7},
    ]
    
    predictions = []
    
    for var in variations:
        design_features = {
            'cell_count': var['cells'],
            'net_count': int(var['cells'] * 0.9),  # Typical ratio
            'die_area_um2': int(var['cells'] * 200),  # Typical density
            'utilization_target': var['util'],
            'aspect_ratio': 1.0,
            'clock_freq_mhz': var['freq'],
            'clock_domains': 1,
            'technology_node_nm': 130,
            'metal_layers': 6,
            'clock_gating_enabled': False,
            'power_gating_enabled': False,
            'hierarchy_depth': 3,
            'macro_count': 0
        }
        
        tool_config = {'threads': 4}
        
        for stage in ['synthesis', 'placement', 'routing']:
            try:
                pred = predictor.predict(stage, design_features, tool_config)
                
                predictions.append({
                    'job_name': f"{var['name']}_{var['freq']}mhz_{int(var['util']*100)}util",
                    'stage': stage,
                    'cell_count': var['cells'],
                    'freq_mhz': var['freq'],
                    'utilization': var['util'],
                    'tech_node': 130,
                    'cpu_avg_%': pred.get('cpu_cores', 4) * 25,  # Estimate utilization
                    'cpu_peak_%': pred.get('cpu_cores', 4) * 50,
                    'memory_gb': pred.get('memory_gb', 1),
                    'duration_sec': pred.get('duration_sec', 60),
                    'source': 'PREDICTED'
                })
            except Exception as e:
                print(f"Warning: Could not predict for {var['name']} {stage}: {e}")
    
    return pd.DataFrame(predictions)

def create_summary_table(df):
    """Create summary table grouped by design size and stage"""
    
    # Define size categories
    def categorize_size(cells):
        if cells < 2000:
            return '1. Tiny (<2K)'
        elif cells < 10000:
            return '2. Small (2-10K)'
        elif cells < 30000:
            return '3. Medium (10-30K)'
        elif cells < 75000:
            return '4. Large (30-75K)'
        elif cells < 200000:
            return '5. XLarge (75-200K)'
        elif cells < 750000:
            return '6. Huge (200-750K)'
        else:
            return '7. Massive (750K+)'
    
    df['size_category'] = df['cell_count'].apply(categorize_size)
    
    # Group by size, stage, and source
    summary = df.groupby(['size_category', 'stage', 'source']).agg({
        'cell_count': ['min', 'max', 'count'],
        'freq_mhz': ['min', 'max'],
        'utilization': ['min', 'max'],
        'memory_gb': ['mean', 'min', 'max'],
        'duration_sec': ['mean', 'min', 'max'],
        'cpu_avg_%': 'mean'
    }).round(2)
    
    return summary

def print_detailed_table(df):
    """Print detailed table with all configurations"""
    
    print("\n" + "="*150)
    print("RESOURCE DEMAND TABLE - DETAILED VIEW")
    print("="*150)
    print()
    
    # Sort by cell count, then stage
    df_sorted = df.sort_values(['cell_count', 'stage', 'freq_mhz'])
    
    # Print header
    print(f"{'Design':<25} {'Stage':<12} {'Cells':>8} {'Freq':>6} {'Util':>5} {'CPU%':>6} {'Memory':>8} {'Duration':>10} {'Source':<10}")
    print(f"{'Name':<25} {'':<12} {'(K)':>8} {'(MHz)':>6} {'':>5} {'(avg)':>6} {'(GB)':>8} {'(sec)':>10} {'':<10}")
    print("-" * 150)
    
    current_size = None
    for _, row in df_sorted.iterrows():
        size_k = row['cell_count'] / 1000
        
        # Add separator between size categories
        if current_size is None or abs(size_k - current_size) > 10:
            if current_size is not None:
                print("-" * 150)
            current_size = size_k
        
        print(f"{row['job_name']:<25} {row['stage']:<12} {size_k:>8.1f} {row['freq_mhz']:>6.0f} {row['utilization']:>5.2f} "
              f"{row['cpu_avg_%']:>6.1f} {row['memory_gb']:>8.2f} {row['duration_sec']:>10.1f} {row['source']:<10}")

def print_stage_comparison(df):
    """Print comparison across stages"""
    
    print("\n" + "="*120)
    print("STAGE COMPARISON - Resource Requirements by Stage")
    print("="*120)
    print()
    
    stages = ['synthesis', 'placement', 'routing']
    
    for stage in stages:
        stage_df = df[df['stage'] == stage]
        
        print(f"\n{stage.upper()} Stage:")
        print(f"  Samples: {len(stage_df)} ({len(stage_df[stage_df['source']=='ACTUAL'])} actual, "
              f"{len(stage_df[stage_df['source']=='PREDICTED'])} predicted)")
        
        if len(stage_df) > 0:
            print(f"  Memory:   {stage_df['memory_gb'].min():.2f} - {stage_df['memory_gb'].max():.2f} GB "
                  f"(avg: {stage_df['memory_gb'].mean():.2f} GB)")
            print(f"  Duration: {stage_df['duration_sec'].min():.1f} - {stage_df['duration_sec'].max():.1f} sec "
                  f"(avg: {stage_df['duration_sec'].mean():.1f} sec)")
            print(f"  CPU:      {stage_df['cpu_avg_%'].min():.1f}% - {stage_df['cpu_avg_%'].max():.1f}% "
                  f"(avg: {stage_df['cpu_avg_%'].mean():.1f}%)")

def print_scaling_analysis(df):
    """Analyze how resources scale with design size"""
    
    print("\n" + "="*120)
    print("SCALING ANALYSIS - How Resources Scale with Design Size")
    print("="*120)
    print()
    
    # Group by cell count ranges
    bins = [0, 10000, 50000, 100000, 500000, 1000000, 10000000]
    labels = ['<10K', '10-50K', '50-100K', '100-500K', '500K-1M', '>1M']
    
    df['size_bin'] = pd.cut(df['cell_count'], bins=bins, labels=labels)
    
    for stage in ['synthesis', 'placement', 'routing']:
        stage_df = df[df['stage'] == stage]
        
        print(f"\n{stage.upper()} Stage Scaling:")
        print(f"  {'Size Range':<12} {'Samples':>8} {'Avg Memory':>12} {'Avg Duration':>14} {'Avg CPU%':>10}")
        print(f"  {'':<12} {'':>8} {'(GB)':>12} {'(sec)':>14} {'':>10}")
        print("  " + "-" * 60)
        
        for size_bin in labels:
            bin_df = stage_df[stage_df['size_bin'] == size_bin]
            if len(bin_df) > 0:
                print(f"  {size_bin:<12} {len(bin_df):>8} {bin_df['memory_gb'].mean():>12.2f} "
                      f"{bin_df['duration_sec'].mean():>14.1f} {bin_df['cpu_avg_%'].mean():>10.1f}")

def print_frequency_impact(df):
    """Analyze impact of clock frequency"""
    
    print("\n" + "="*120)
    print("FREQUENCY IMPACT - How Clock Frequency Affects Resources")
    print("="*120)
    print()
    
    freq_ranges = df.groupby(['freq_mhz', 'stage']).agg({
        'memory_gb': 'mean',
        'duration_sec': 'mean',
        'cpu_avg_%': 'mean',
        'cell_count': 'count'
    }).round(2)
    
    print(freq_ranges)

def main():
    """Generate and display comprehensive resource table"""
    
    print("="*120)
    print("GENERATING RESOURCE DEMAND TABLE")
    print("="*120)
    
    # Load actual data
    print("\nLoading actual collected data...")
    actual_df = load_actual_data()
    print(f"Loaded {len(actual_df)} actual measurements")
    
    # Generate predictions
    print("\nGenerating predictions for various configurations...")
    predicted_df = generate_predictions()
    print(f"Generated {len(predicted_df)} predictions")
    
    # Combine
    combined_df = pd.concat([actual_df, predicted_df], ignore_index=True)
    print(f"\nTotal entries: {len(combined_df)}")
    
    # Print tables
    print_detailed_table(combined_df)
    print_stage_comparison(combined_df)
    print_scaling_analysis(combined_df)
    print_frequency_impact(combined_df)
    
    # Save to CSV
    output_file = 'data/results/resource_demand_table.csv'
    combined_df.to_csv(output_file, index=False)
    print(f"\n✓ Table saved to: {output_file}")
    
    # Print summary statistics
    print("\n" + "="*120)
    print("SUMMARY STATISTICS")
    print("="*120)
    print()
    print(f"Total configurations analyzed: {len(combined_df)}")
    print(f"  Actual measurements: {len(actual_df)} ({len(actual_df)/len(combined_df)*100:.1f}%)")
    print(f"  Predicted values: {len(predicted_df)} ({len(predicted_df)/len(combined_df)*100:.1f}%)")
    print()
    print(f"Design size range: {combined_df['cell_count'].min():,} - {combined_df['cell_count'].max():,} cells")
    print(f"Frequency range: {combined_df['freq_mhz'].min():.0f} - {combined_df['freq_mhz'].max():.0f} MHz")
    print(f"Utilization range: {combined_df['utilization'].min():.2f} - {combined_df['utilization'].max():.2f}")
    print()
    print(f"Memory range: {combined_df['memory_gb'].min():.2f} - {combined_df['memory_gb'].max():.2f} GB")
    print(f"Duration range: {combined_df['duration_sec'].min():.1f} - {combined_df['duration_sec'].max():.1f} sec")
    print(f"CPU utilization range: {combined_df['cpu_avg_%'].min():.1f}% - {combined_df['cpu_avg_%'].max():.1f}%")

if __name__ == "__main__":
    main()
