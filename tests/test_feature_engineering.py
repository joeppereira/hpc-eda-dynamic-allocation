#!/usr/bin/env python3
"""Unit tests for feature engineering"""

import sys
sys.path.append('.')

import numpy as np
from prediction.model import ResourcePredictor


def test_extract_features_basic():
    """Test basic feature extraction"""
    predictor = ResourcePredictor()
    
    design_features = {
        'cell_count': 5000,
        'net_count': 4500,
        'die_area_um2': 1000000,
        'utilization_target': 0.6,
        'clock_freq_mhz': 100
    }
    
    tool_config = {'threads': 4}
    
    features = predictor.extract_features(design_features, tool_config)
    
    # Check shape
    assert len(features) == 17, f"Expected 17 features, got {len(features)}"
    
    # Check all features are numeric
    assert np.all(np.isfinite(features)), "All features should be finite"
    
    # Check specific values (with tolerance for float32)
    assert np.isclose(features[0], np.log1p(5000), rtol=1e-5), "log_cell_count incorrect"
    assert np.isclose(features[3], 0.6, rtol=1e-5), "utilization incorrect"
    assert np.isclose(features[5], 0.1, rtol=1e-5), "clock_freq_ghz incorrect (100MHz = 0.1GHz)"
    
    print("✓ test_extract_features_basic passed")


def test_extract_features_defaults():
    """Test feature extraction with missing values"""
    predictor = ResourcePredictor()
    
    design_features = {'cell_count': 1000}
    tool_config = {}
    
    features = predictor.extract_features(design_features, tool_config)
    
    # Should use defaults for missing values
    assert np.all(np.isfinite(features)), "Should handle missing values with defaults"
    
    print("✓ test_extract_features_defaults passed")


def test_feature_names():
    """Test that feature names are set correctly"""
    predictor = ResourcePredictor()
    
    design_features = {'cell_count': 1000}
    tool_config = {}
    
    predictor.extract_features(design_features, tool_config)
    
    assert len(predictor.feature_names) == 17, "Should have 17 feature names"
    assert 'log_cell_count' in predictor.feature_names
    assert 'complexity_score' in predictor.feature_names
    
    print("✓ test_feature_names passed")


if __name__ == "__main__":
    test_extract_features_basic()
    test_extract_features_defaults()
    test_feature_names()
    print("\nAll feature engineering tests passed!")
