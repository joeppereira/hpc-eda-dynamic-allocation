#!/bin/bash
# Quick demo script for HPC Resource Optimization Dashboard

set -e

echo "=========================================="
echo "HPC Resource Optimization Dashboard Demo"
echo "=========================================="
echo ""

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Step 1: Generate sample data
echo -e "${BLUE}Step 1: Generating sample data...${NC}"
python3 scripts/generate_sample_data.py --jobs 50
echo ""

# Step 2: Start dashboard
echo -e "${BLUE}Step 2: Starting dashboard...${NC}"
export DB_PATH=hpc_metrics.db
cd dashboard
python3 app.py &
DASHBOARD_PID=$!
cd ..

echo -e "${GREEN}✓ Dashboard started (PID: $DASHBOARD_PID)${NC}"
echo ""

# Wait for dashboard to start
sleep 3

# Step 3: Test API endpoints
echo -e "${BLUE}Step 3: Testing API endpoints...${NC}"
echo ""

echo "Summary Statistics:"
curl -s http://localhost:5000/api/stats/summary | python3 -m json.tool | head -20
echo ""

echo "Recent Jobs (first 3):"
curl -s http://localhost:5000/api/jobs/recent | python3 -m json.tool | head -40
echo ""

# Step 4: Display access info
echo -e "${GREEN}=========================================="
echo -e "✓ Dashboard Demo Ready!"
echo -e "==========================================${NC}"
echo ""
echo "Access dashboard at: http://localhost:5000"
echo ""
echo "Features:"
echo "  • Real-time resource monitoring"
echo "  • Before/after optimization comparison"
echo "  • Cost savings analysis"
echo "  • Design attribute correlation"
echo "  • SPANK plugin integration"
echo ""
echo "To stop dashboard:"
echo "  kill $DASHBOARD_PID"
echo ""
echo "Press Ctrl+C to exit (dashboard will keep running)"
echo ""

# Keep script running
wait $DASHBOARD_PID
