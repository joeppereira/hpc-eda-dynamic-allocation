#!/usr/bin/env python3
"""
Train prediction model from database
"""

import sys
from pathlib import Path
import pandas as pd
from sqlalchemy import create_engine
from model import ResourcePredictor

# Add database to path
sys.path.append(str(Path(__file__).parent.parent / 'database'))
from schema import Job, DesignFeatures, ToolConfig, JobStage, StageResources


def load_training_data(db_path: str = 'sqlite:///data/metrics.db') -> pd.DataFrame:
    """Load training data from database"""
    
    engine = create_engine(db_path, echo=False)
    
    # Query to join all tables
    query = """
    SELECT 
        js.stage_name,
        js.duration_sec,
        sr.cpu_util_avg,
        sr.cpu_util_peak,
        sr.memory_peak_gb,
        sr.memory_avg_gb,
        df.cell_count,
        df.net_count,
        df.die_area_um2,
        df.utilization_target,
        df.aspect_ratio,
        df.clock_freq_mhz,
        df.clock_domains,
        df.technology_node_nm,
        df.metal_layers,
        df.clock_gating_enabled,
        df.power_gating_enabled,
        df.hierarchy_depth,
        df.macro_count,
        tc.config_json
    FROM job_stages js
    JOIN stage_resources sr ON js.id = sr.stage_id
    JOIN jobs j ON js.job_id = j.id
    JOIN design_features df ON j.id = df.job_id
    JOIN tool_configs tc ON j.id = tc.job_id
    """
    
    df = pd.read_sql(query, engine)
    
    if len(df) == 0:
        print("No training data found in database!")
        return None
    
    print(f"Loaded {len(df)} stage records from database")
    print(f"Stages: {df['stage_name'].unique()}")
    
    # Prepare data for model
    training_data = []
    for _, row in df.iterrows():
        design_features = {
            'cell_count': row['cell_count'],
            'net_count': row['net_count'],
            'die_area_um2': row['die_area_um2'],
            'utilization_target': row['utilization_target'],
            'aspect_ratio': row['aspect_ratio'],
            'clock_freq_mhz': row['clock_freq_mhz'],
            'clock_domains': row['clock_domains'],
            'technology_node_nm': row['technology_node_nm'],
            'metal_layers': row['metal_layers'],
            'clock_gating_enabled': bool(row['clock_gating_enabled']),
            'power_gating_enabled': bool(row['power_gating_enabled']),
            'hierarchy_depth': row['hierarchy_depth'],
            'macro_count': row['macro_count']
        }
        
        # Parse tool config JSON
        import json
        tool_config = json.loads(row['config_json']) if row['config_json'] else {}
        
        training_data.append({
            'stage_name': row['stage_name'],
            'design_features': design_features,
            'tool_config': tool_config,
            'cpu_cores': row['cpu_util_peak'] / 100.0 * tool_config.get('threads', 4),  # Estimate
            'memory_gb': row['memory_peak_gb'],
            'duration_sec': row['duration_sec']
        })
    
    return pd.DataFrame(training_data)


def main():
    """Train and save model"""
    
    # Load data
    print("Loading training data from database...")
    data = load_training_data()
    
    if data is None or len(data) < 5:
        print("Insufficient training data. Need at least 5 samples.")
        print("Run some test jobs first to collect data.")
        return
    
    print(f"\nTraining data summary:")
    print(f"  Total samples: {len(data)}")
    print(f"  Stages: {', '.join(data['stage_name'].unique())}")
    print(f"  Samples per stage:")
    for stage, count in data['stage_name'].value_counts().items():
        print(f"    {stage}: {count}")
    
    # Train model
    print("\nTraining Ridge regression models...")
    predictor = ResourcePredictor()
    predictor.train(data, alpha=1.0)
    
    # Evaluate (simple train set evaluation for now)
    print("\nEvaluating model on training data...")
    metrics = predictor.evaluate(data)
    
    print("\nModel Performance:")
    for model_key, model_metrics in metrics.items():
        print(f"\n{model_key}:")
        print(f"  MAE:  {model_metrics['mae']:.3f}")
        print(f"  RMSE: {model_metrics['rmse']:.3f}")
        print(f"  R²:   {model_metrics['r2']:.3f}")
        print(f"  MAPE: {model_metrics['mape']:.1f}%")
    
    # Save model
    model_path = Path('prediction/trained_model.pkl')
    predictor.save(model_path)
    
    print(f"\n✓ Model training complete!")
    print(f"✓ Model saved to {model_path}")


if __name__ == "__main__":
    main()
