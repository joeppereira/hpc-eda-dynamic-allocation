#!/bin/bash
# Test the prediction API

echo "Starting prediction API..."
PYTHONPATH=/Users/spereirj/dynamic_allocation python3 prediction/api.py &
API_PID=$!

# Wait for API to start
sleep 3

echo ""
echo "Testing API endpoints..."
echo ""

# Test health endpoint
echo "1. Health check:"
curl -s http://localhost:8000/health | python3 -m json.tool
echo ""

# Test prediction endpoint
echo "2. Predict resources for placement stage:"
curl -s -X POST http://localhost:8000/predict \
  -H "Content-Type: application/json" \
  -d '{
    "stage_name": "placement",
    "design_features": {
      "cell_count": 25000,
      "net_count": 22500,
      "die_area_um2": 5000000,
      "utilization_target": 0.65,
      "clock_freq_mhz": 250
    },
    "tool_config": {
      "tool": "openroad",
      "threads": 8
    }
  }' | python3 -m json.tool
echo ""

# Test predict all stages
echo "3. Predict all stages:"
curl -s -X POST http://localhost:8000/predict_all_stages \
  -H "Content-Type: application/json" \
  -d '{
    "cell_count": 25000,
    "net_count": 22500,
    "die_area_um2": 5000000,
    "utilization_target": 0.65,
    "clock_freq_mhz": 250
  }' | python3 -m json.tool
echo ""

# Stop API
echo "Stopping API..."
kill $API_PID

echo "✓ API test complete!"
