#!/bin/bash
# Enhanced test with clock frequency and geometry variations

set -e

echo "=========================================="
echo "Enhanced HPC Resource Optimization Test"
echo "With Clock Frequency & Geometry Variations"
echo "=========================================="
echo ""

# Clean previous data
rm -rf data/metrics/*.json data/metrics.db

# Create directories
mkdir -p data/metrics data/temp

# Initialize database
echo "Initializing database..."
python3 database/schema.py

echo ""
echo "=========================================="
echo "Running simulated jobs with variations..."
echo "=========================================="

# Test matrix: Size × Frequency × Technology × Utilization

# Small designs (5K cells)
echo ""
echo "=== Small Designs (5K cells) ==="

python3 scripts/simulate_openroad_job.py \
  --name small_100mhz_130nm_50util \
  --cells 5000 --freq 100 --util 0.5

python3 scripts/simulate_openroad_job.py \
  --name small_500mhz_130nm_70util \
  --cells 5000 --freq 500 --util 0.7

python3 scripts/simulate_openroad_job.py \
  --name small_200mhz_45nm_60util \
  --cells 5000 --freq 200 --util 0.6

# Medium designs (20K cells)
echo ""
echo "=== Medium Designs (20K cells) ==="

python3 scripts/simulate_openroad_job.py \
  --name medium_100mhz_130nm_60util \
  --cells 20000 --freq 100 --util 0.6

python3 scripts/simulate_openroad_job.py \
  --name medium_500mhz_130nm_70util \
  --cells 20000 --freq 500 --util 0.7

python3 scripts/simulate_openroad_job.py \
  --name medium_200mhz_45nm_65util \
  --cells 20000 --freq 200 --util 0.65

# Large designs (50K cells)
echo ""
echo "=== Large Designs (50K cells) ==="

python3 scripts/simulate_openroad_job.py \
  --name large_100mhz_130nm_60util \
  --cells 50000 --freq 100 --util 0.6

python3 scripts/simulate_openroad_job.py \
  --name large_500mhz_130nm_70util \
  --cells 50000 --freq 500 --util 0.7

python3 scripts/simulate_openroad_job.py \
  --name large_1000mhz_45nm_70util \
  --cells 50000 --freq 1000 --util 0.7

# Import metrics
echo ""
echo "=========================================="
echo "Importing metrics to database..."
echo "=========================================="
python3 database/import_metrics.py data/metrics

# Train model
echo ""
echo "=========================================="
echo "Training prediction model..."
echo "=========================================="
PYTHONPATH=/Users/spereirj/dynamic_allocation python3 prediction/train_model.py

# Test predictions
echo ""
echo "=========================================="
echo "Testing predictions..."
echo "=========================================="
PYTHONPATH=/Users/spereirj/dynamic_allocation python3 scripts/test_prediction.py

# Analyze results
echo ""
echo "=========================================="
echo "Analyzing results..."
echo "=========================================="
PYTHONPATH=/Users/spereirj/dynamic_allocation python3 scripts/analyze_results.py

echo ""
echo "=========================================="
echo "✓ Enhanced test complete!"
echo "=========================================="
echo ""
echo "Key variations tested:"
echo "  - Cell counts: 5K, 20K, 50K"
echo "  - Frequencies: 100MHz, 200MHz, 500MHz, 1GHz"
echo "  - Technology nodes: 130nm, 45nm"
echo "  - Utilization: 50%, 60%, 65%, 70%"
echo ""
echo "Results:"
echo "  - Metrics: data/metrics/"
echo "  - Database: data/metrics.db"
echo "  - Model: prediction/trained_model.pkl"
echo "  - Plots: data/results/"
echo ""
