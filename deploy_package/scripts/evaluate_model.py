#!/usr/bin/env python3
"""
Comprehensive model evaluation with train/test split
"""

import sys
from pathlib import Path
sys.path.append(str(Path(__file__).parent.parent))

import pandas as pd
import numpy as np
from sklearn.model_selection import train_test_split
from prediction.model import ResourcePredictor

# Import load_training_data function
sys.path.append(str(Path(__file__).parent.parent / 'prediction'))
from train_model import load_training_data


def evaluate_with_split(data: pd.DataFrame, test_size: float = 0.2):
    """Evaluate model with proper train/test split"""
    
    print(f"\nSplitting data: {int((1-test_size)*100)}% train, {int(test_size*100)}% test")
    
    # Split data
    train_data, test_data = train_test_split(data, test_size=test_size, random_state=42)
    
    print(f"Train samples: {len(train_data)}")
    print(f"Test samples: {len(test_data)}")
    
    # Train model
    print("\nTraining model on train set...")
    predictor = ResourcePredictor()
    predictor.train(train_data, alpha=1.0)
    
    # Evaluate on test set
    print("\nEvaluating on test set...")
    test_metrics = predictor.evaluate(test_data)
    
    return predictor, test_metrics, train_data, test_data


def print_detailed_metrics(metrics: dict):
    """Print detailed performance metrics"""
    print("\n" + "="*80)
    print("MODEL PERFORMANCE ON TEST SET")
    print("="*80)
    
    # Group by stage
    stages = set(key.split('_')[0] for key in metrics.keys())
    
    for stage in sorted(stages):
        print(f"\n--- {stage.upper()} Stage ---")
        
        for resource in ['cpu_cores', 'memory_gb', 'duration_sec']:
            model_key = f"{stage}_{resource}"
            
            if model_key not in metrics:
                continue
            
            m = metrics[model_key]
            print(f"\n{resource}:")
            print(f"  MAE:  {m['mae']:.4f}")
            print(f"  RMSE: {m['rmse']:.4f}")
            print(f"  R²:   {m['r2']:.4f}")
            print(f"  MAPE: {m['mape']:.2f}%")
            
            # Accuracy assessment
            if m['r2'] > 0.85:
                status = "✓ Excellent"
            elif m['r2'] > 0.70:
                status = "✓ Good"
            elif m['r2'] > 0.50:
                status = "⚠ Acceptable"
            else:
                status = "✗ Needs improvement"
            
            print(f"  Status: {status}")


def check_accuracy_requirement(metrics: dict, threshold: float = 0.85):
    """Check if model meets 85% accuracy requirement"""
    print("\n" + "="*80)
    print("ACCURACY REQUIREMENT CHECK (R² > 0.85)")
    print("="*80)
    
    passed = []
    failed = []
    
    for model_key, m in metrics.items():
        r2 = m['r2']
        if r2 >= threshold:
            passed.append((model_key, r2))
        else:
            failed.append((model_key, r2))
    
    print(f"\n✓ Passed ({len(passed)}/{len(metrics)}):")
    for key, r2 in passed:
        print(f"  {key:30s}: R² = {r2:.3f}")
    
    if failed:
        print(f"\n✗ Failed ({len(failed)}/{len(metrics)}):")
        for key, r2 in failed:
            print(f"  {key:30s}: R² = {r2:.3f}")
    
    overall_pass = len(passed) / len(metrics) >= 0.67  # At least 2/3 should pass
    
    print(f"\nOverall: {'✓ PASS' if overall_pass else '✗ FAIL'}")
    print(f"  {len(passed)}/{len(metrics)} models meet R² > {threshold} threshold")
    
    if not overall_pass:
        print("\nRecommendations:")
        print("  - Collect more training data (currently only 7 jobs)")
        print("  - Add more design variations (frequency, utilization)")
        print("  - Consider polynomial features for non-linear relationships")
    
    return overall_pass


def analyze_feature_importance(predictor: ResourcePredictor):
    """Analyze which features are most important"""
    print("\n" + "="*80)
    print("FEATURE IMPORTANCE ANALYSIS")
    print("="*80)
    
    for stage in predictor.stages:
        print(f"\n--- {stage.upper()} Stage ---")
        
        for resource in ['memory_gb', 'duration_sec']:
            model_key = f"{stage}_{resource}"
            
            if model_key not in predictor.models:
                continue
            
            model = predictor.models[model_key]
            coefs = model.named_steps['regressor'].coef_
            
            # Get top 5 features
            importance = sorted(
                zip(predictor.feature_names, coefs),
                key=lambda x: abs(x[1]),
                reverse=True
            )[:5]
            
            print(f"\n{resource} - Top 5 features:")
            for feat, coef in importance:
                direction = "↑" if coef > 0 else "↓"
                print(f"  {feat:25s}: {coef:+.4f} {direction}")


def main():
    """Run comprehensive model evaluation"""
    print("="*80)
    print("MODEL EVALUATION")
    print("="*80)
    
    # Load data
    print("\nLoading data from database...")
    data = load_training_data()
    
    if data is None or len(data) < 5:
        print("ERROR: Insufficient data for evaluation")
        return
    
    print(f"Loaded {len(data)} samples")
    
    # Check if we have enough data for split
    if len(data) < 10:
        print("\nWARNING: Only {len(data)} samples - using full dataset for evaluation")
        print("Recommend collecting at least 20 samples for proper train/test split")
        
        # Train on full dataset
        predictor = ResourcePredictor()
        predictor.train(data, alpha=1.0)
        metrics = predictor.evaluate(data)
        
        print("\n(Evaluating on training data - may be optimistic)")
    else:
        # Proper train/test split
        predictor, metrics, train_data, test_data = evaluate_with_split(data, test_size=0.2)
    
    # Print detailed metrics
    print_detailed_metrics(metrics)
    
    # Check accuracy requirement
    check_accuracy_requirement(metrics, threshold=0.85)
    
    # Feature importance
    analyze_feature_importance(predictor)
    
    print("\n" + "="*80)
    print("EVALUATION COMPLETE")
    print("="*80)


if __name__ == "__main__":
    main()
