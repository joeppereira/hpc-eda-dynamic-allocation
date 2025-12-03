#!/bin/bash
# Complete local end-to-end test flow

set -e  # Exit on error

echo "=========================================="
echo "HPC Resource Optimization - Local Test"
echo "=========================================="
echo ""

# Create directories
echo "Creating directories..."
mkdir -p data/metrics data/temp

# Initialize database
echo ""
echo "Initializing database..."
python3 database/schema.py

# Run simulated jobs with variations
echo ""
echo "=========================================="
echo "Running simulated OpenROAD jobs..."
echo "=========================================="

# Small design variations
echo ""
echo "Job 1: Small design, 100MHz, 50% util"
python3 scripts/simulate_openroad_job.py --name small_100mhz_50util --cells 5000 --freq 100 --util 0.5

echo ""
echo "Job 2: Small design, 200MHz, 60% util"
python3 scripts/simulate_openroad_job.py --name small_200mhz_60util --cells 5000 --freq 200 --util 0.6

echo ""
echo "Job 3: Small design, 500MHz, 70% util"
python3 scripts/simulate_openroad_job.py --name small_500mhz_70util --cells 5000 --freq 500 --util 0.7

# Medium design variations
echo ""
echo "Job 4: Medium design, 100MHz, 60% util"
python3 scripts/simulate_openroad_job.py --name medium_100mhz_60util --cells 20000 --freq 100 --util 0.6

echo ""
echo "Job 5: Medium design, 200MHz, 70% util"
python3 scripts/simulate_openroad_job.py --name medium_200mhz_70util --cells 20000 --freq 200 --util 0.7

# Large design variations
echo ""
echo "Job 6: Large design, 100MHz, 60% util"
python3 scripts/simulate_openroad_job.py --name large_100mhz_60util --cells 50000 --freq 100 --util 0.6

echo ""
echo "Job 7: Large design, 200MHz, 70% util"
python3 scripts/simulate_openroad_job.py --name large_200mhz_70util --cells 50000 --freq 200 --util 0.7

# Import metrics to database
echo ""
echo "=========================================="
echo "Importing metrics to database..."
echo "=========================================="
python3 database/import_metrics.py data/metrics

# Train prediction model
echo ""
echo "=========================================="
echo "Training prediction model..."
echo "=========================================="
python3 prediction/train_model.py

# Test prediction
echo ""
echo "=========================================="
echo "Testing predictions..."
echo "=========================================="
python3 scripts/test_prediction.py

echo ""
echo "=========================================="
echo "✓ Local test complete!"
echo "=========================================="
echo ""
echo "Next steps:"
echo "  1. Review metrics in data/metrics/"
echo "  2. Check database: sqlite3 data/metrics.db"
echo "  3. Start API: python3 prediction/api.py"
echo "  4. View results: python3 scripts/analyze_results.py"
echo ""
