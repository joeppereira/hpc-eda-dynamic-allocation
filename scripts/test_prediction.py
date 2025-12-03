#!/usr/bin/env python3
"""
Test prediction model with sample designs
"""

import sys
from pathlib import Path

# Add parent directory to path
sys.path.append(str(Path(__file__).parent.parent))

from prediction.model import ResourcePredictor


def main():
    # Load trained model
    model_path = Path('prediction/trained_model.pkl')
    
    if not model_path.exists():
        print("Error: Model not found. Train model first.")
        return
    
    print("Loading trained model...")
    predictor = ResourcePredictor.load(model_path)
    
    print(f"Model loaded successfully!")
    print(f"Available stages: {predictor.stages}\n")
    
    # Test predictions for different designs
    test_designs = [
        {
            'name': 'Small design (10K cells, 100MHz)',
            'design_features': {
                'cell_count': 10000,
                'net_count': 9000,
                'die_area_um2': 2000000,
                'utilization_target': 0.6,
                'aspect_ratio': 1.0,
                'clock_freq_mhz': 100,
                'clock_domains': 1,
                'technology_node_nm': 130,
                'metal_layers': 6,
                'clock_gating_enabled': False,
                'power_gating_enabled': False,
                'hierarchy_depth': 3,
                'macro_count': 0
            },
            'tool_config': {'tool': 'openroad', 'threads': 4}
        },
        {
            'name': 'Large design (100K cells, 500MHz)',
            'design_features': {
                'cell_count': 100000,
                'net_count': 90000,
                'die_area_um2': 20000000,
                'utilization_target': 0.7,
                'aspect_ratio': 1.0,
                'clock_freq_mhz': 500,
                'clock_domains': 2,
                'technology_node_nm': 130,
                'metal_layers': 6,
                'clock_gating_enabled': True,
                'power_gating_enabled': False,
                'hierarchy_depth': 5,
                'macro_count': 4
            },
            'tool_config': {'tool': 'openroad', 'threads': 8}
        }
    ]
    
    for test in test_designs:
        print("="*60)
        print(f"Test: {test['name']}")
        print("="*60)
        
        for stage in predictor.stages:
            pred = predictor.predict(
                stage,
                test['design_features'],
                test['tool_config']
            )
            
            print(f"\n{stage}:")
            print(f"  CPU cores:  {pred['cpu_cores']:.1f}")
            print(f"  Memory:     {pred['memory_gb']:.1f} GB")
            print(f"  Duration:   {pred['duration_sec']:.0f} sec ({pred['duration_sec']/60:.1f} min)")
        
        # Total estimates
        total_duration = sum(
            predictor.predict(stage, test['design_features'], test['tool_config'])['duration_sec']
            for stage in predictor.stages
        )
        max_memory = max(
            predictor.predict(stage, test['design_features'], test['tool_config'])['memory_gb']
            for stage in predictor.stages
        )
        
        print(f"\nTotal estimated duration: {total_duration:.0f} sec ({total_duration/60:.1f} min)")
        print(f"Peak memory requirement:  {max_memory:.1f} GB")
        print()
    
    print("="*60)
    print("✓ Prediction test complete!")
    print("="*60)


if __name__ == "__main__":
    main()
