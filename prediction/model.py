#!/usr/bin/env python3
"""
Ridge regression model for resource prediction
"""

import numpy as np
import pandas as pd
import pickle
from pathlib import Path
from typing import Dict, Tuple
from sklearn.linear_model import Ridge
from sklearn.preprocessing import StandardScaler
from sklearn.pipeline import Pipeline
from sklearn.model_selection import train_test_split
from sklearn.metrics import mean_absolute_error, mean_squared_error, r2_score


class ResourcePredictor:
    """Predict resource requirements using Ridge regression"""
    
    def __init__(self):
        self.models = {}  # Separate model per stage and resource type
        self.feature_names = []
        self.stages = []
        
    def extract_features(self, design_features: Dict, tool_config: Dict) -> np.ndarray:
        """
        Extract and normalize features from design config
        
        Args:
            design_features: Design parameters
            tool_config: Tool configuration
            
        Returns:
            Feature vector
        """
        features = [
            # Design size features (log-transformed)
            np.log1p(design_features.get('cell_count', 1)),
            np.log1p(design_features.get('net_count', 1)),
            np.log1p(design_features.get('die_area_um2', 1)),
            design_features.get('utilization_target', 0.6),
            design_features.get('aspect_ratio', 1.0),
            
            # Timing features (normalized)
            design_features.get('clock_freq_mhz', 100) / 1000.0,  # to GHz
            design_features.get('clock_domains', 1),
            
            # Technology features
            design_features.get('technology_node_nm', 130) / 130.0,  # normalized
            design_features.get('metal_layers', 6),
            
            # Power features (binary)
            int(design_features.get('clock_gating_enabled', False)),
            int(design_features.get('power_gating_enabled', False)),
            
            # Complexity features
            design_features.get('hierarchy_depth', 1),
            design_features.get('macro_count', 0),
            
            # Derived features
            design_features.get('cell_count', 1) / max(design_features.get('die_area_um2', 1), 1),  # density
            design_features.get('net_count', 1) / max(design_features.get('cell_count', 1), 1),  # connectivity
            # REMOVED: complexity_score (freq * cells) - causes bad extrapolation
            # Frequency has minimal impact on memory based on actual data
            0.0,  # placeholder to keep feature count consistent
            
            # Tool config
            tool_config.get('threads', 4),
        ]
        
        if not self.feature_names:
            self.feature_names = [
                'log_cell_count', 'log_net_count', 'log_die_area',
                'utilization', 'aspect_ratio', 'clock_freq_ghz', 'clock_domains',
                'tech_node_norm', 'metal_layers', 'clock_gating', 'power_gating',
                'hierarchy_depth', 'macro_count', 'cell_density', 'connectivity',
                'complexity_score', 'threads'
            ]
        
        return np.array(features, dtype=np.float32)
    
    def train(self, data: pd.DataFrame, alpha: float = 1.0):
        """
        Train models on historical data
        
        Args:
            data: DataFrame with columns: stage_name, design_features, tool_config,
                  cpu_cores, memory_gb, duration_sec
            alpha: Ridge regularization parameter
        """
        self.stages = data['stage_name'].unique()
        
        for stage in self.stages:
            stage_data = data[data['stage_name'] == stage]
            
            if len(stage_data) < 3:
                print(f"Warning: Only {len(stage_data)} samples for stage {stage}, skipping")
                continue
            
            # Extract features
            X = np.array([
                self.extract_features(row['design_features'], row['tool_config'])
                for _, row in stage_data.iterrows()
            ])
            
            # Train separate model for each resource type
            for resource in ['cpu_cores', 'memory_gb', 'duration_sec']:
                if resource not in stage_data.columns:
                    continue
                
                y = stage_data[resource].values
                
                # Create pipeline with scaling and Ridge regression
                model = Pipeline([
                    ('scaler', StandardScaler()),
                    ('regressor', Ridge(alpha=alpha))
                ])
                
                # Train
                model.fit(X, y)
                
                # Store model
                model_key = f"{stage}_{resource}"
                self.models[model_key] = model
                
                # Print coefficients for interpretability
                coefs = model.named_steps['regressor'].coef_
                print(f"\n{stage} - {resource} coefficients:")
                for name, coef in sorted(zip(self.feature_names, coefs), 
                                        key=lambda x: abs(x[1]), reverse=True)[:5]:
                    print(f"  {name:20s}: {coef:+.4f}")
        
        print(f"\nTrained {len(self.models)} models across {len(self.stages)} stages")
    
    def predict(self, stage_name: str, design_features: Dict, tool_config: Dict) -> Dict:
        """
        Predict resource requirements for a stage
        
        Args:
            stage_name: Name of the stage
            design_features: Design parameters
            tool_config: Tool configuration
            
        Returns:
            Dictionary with predicted cpu_cores, memory_gb, duration_sec
        """
        X = self.extract_features(design_features, tool_config).reshape(1, -1)
        
        # Check if we're extrapolating beyond training data
        cell_count = design_features.get('cell_count', 0)
        freq_mhz = design_features.get('clock_freq_mhz', 0)
        
        # Training data range: 5K-50K cells, 100-500 MHz
        extrapolating = (cell_count > 100000 or freq_mhz > 600)
        
        predictions = {}
        for resource in ['cpu_cores', 'memory_gb', 'duration_sec']:
            model_key = f"{stage_name}_{resource}"
            
            if model_key in self.models:
                pred = self.models[model_key].predict(X)[0]
                
                # Apply realistic bounds based on actual data
                if resource == 'memory_gb':
                    # Memory scales primarily with cell count, not frequency
                    # Based on actual data: ~0.2 GB per 50K cells for synthesis
                    # ~0.12 GB per 50K cells for placement
                    max_reasonable = (cell_count / 50000) * 0.3  # Conservative upper bound
                    pred = min(pred, max_reasonable)
                
                predictions[resource] = max(pred, 0)  # Ensure non-negative
                
                # Add confidence flag
                if extrapolating:
                    predictions[f'{resource}_confidence'] = 'low'
            else:
                # Fallback defaults
                defaults = {'cpu_cores': 4, 'memory_gb': 8, 'duration_sec': 600}
                predictions[resource] = defaults[resource]
                predictions[f'{resource}_confidence'] = 'default'
        
        return predictions
    
    def evaluate(self, data: pd.DataFrame) -> Dict:
        """
        Evaluate model accuracy on test data
        
        Args:
            data: Test dataset
            
        Returns:
            Dictionary of metrics
        """
        metrics = {}
        
        for stage in self.stages:
            stage_data = data[data['stage_name'] == stage]
            
            if len(stage_data) == 0:
                continue
            
            X = np.array([
                self.extract_features(row['design_features'], row['tool_config'])
                for _, row in stage_data.iterrows()
            ])
            
            for resource in ['cpu_cores', 'memory_gb', 'duration_sec']:
                model_key = f"{stage}_{resource}"
                
                if model_key not in self.models or resource not in stage_data.columns:
                    continue
                
                y_true = stage_data[resource].values
                y_pred = self.models[model_key].predict(X)
                
                mae = mean_absolute_error(y_true, y_pred)
                rmse = np.sqrt(mean_squared_error(y_true, y_pred))
                r2 = r2_score(y_true, y_pred)
                mape = np.mean(np.abs((y_true - y_pred) / (y_true + 1e-6))) * 100
                
                metrics[model_key] = {
                    'mae': mae,
                    'rmse': rmse,
                    'r2': r2,
                    'mape': mape
                }
        
        return metrics
    
    def save(self, filepath: Path):
        """Save model to disk"""
        filepath.parent.mkdir(parents=True, exist_ok=True)
        
        # Save as dict to avoid pickle module issues
        model_data = {
            'models': self.models,
            'feature_names': self.feature_names,
            'stages': self.stages
        }
        
        with open(filepath, 'wb') as f:
            pickle.dump(model_data, f)
        print(f"Model saved to {filepath}")
    
    @staticmethod
    def load(filepath: Path) -> 'ResourcePredictor':
        """Load model from disk"""
        with open(filepath, 'rb') as f:
            model_data = pickle.load(f)
        
        predictor = ResourcePredictor()
        predictor.models = model_data['models']
        predictor.feature_names = model_data['feature_names']
        predictor.stages = model_data['stages']
        
        return predictor


if __name__ == "__main__":
    # Example usage
    print("ResourcePredictor initialized")
    print("Use train() method with historical data to train models")
