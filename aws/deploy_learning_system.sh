#!/bin/bash
# Deploy learning-based resource allocation system to AWS Parallel Cluster

set -e

echo "════════════════════════════════════════════════════════════"
echo "  Deploy Learning-Based Resource Allocation System"
echo "════════════════════════════════════════════════════════════"
echo ""

HEAD_NODE=${1:-""}

if [ -z "$HEAD_NODE" ]; then
    echo "Usage: $0 <head-node-address>"
    echo "Example: $0 ec2-user@ec2-xx-xx-xx-xx.compute.amazonaws.com"
    exit 1
fi

echo "Target: $HEAD_NODE"
echo ""

# Step 1: Copy files to head node
echo "Step 1: Copying files to head node..."
echo "────────────────────────────────────────────────────────────"

scp slurm/job_submit_learning.lua ${HEAD_NODE}:~/
scp prediction/learning_api.py ${HEAD_NODE}:~/
scp prediction/model.py ${HEAD_NODE}:~/
scp database/schema.py ${HEAD_NODE}:~/
scp requirements.txt ${HEAD_NODE}:~/

echo "✓ Files copied"
echo ""

# Step 2: Install on head node
echo "Step 2: Installing on head node..."
echo "────────────────────────────────────────────────────────────"

ssh ${HEAD_NODE} << 'EOSSH'
set -e

echo "Installing Python dependencies..."
pip3 install fastapi uvicorn sqlalchemy psutil scikit-learn --user

echo ""
echo "Setting up directories..."
mkdir -p ~/data ~/models ~/logs

echo ""
echo "Initializing database..."
python3 << 'EOPY'
from database.schema import init_database
engine = init_database('sqlite:///data/metrics.db')
print("✓ Database initialized")
EOPY

echo ""
echo "Installing job_submit plugin..."
sudo cp ~/job_submit_learning.lua /opt/slurm/etc/job_submit.lua
sudo chown slurm:slurm /opt/slurm/etc/job_submit.lua
sudo chmod 644 /opt/slurm/etc/job_submit.lua

echo ""
echo "Configuring SLURM..."
if ! grep -q "JobSubmitPlugins=lua" /opt/slurm/etc/slurm.conf; then
    echo "JobSubmitPlugins=lua" | sudo tee -a /opt/slurm/etc/slurm.conf
    echo "✓ Added JobSubmitPlugins=lua to slurm.conf"
else
    echo "✓ JobSubmitPlugins already configured"
fi

echo ""
echo "Creating systemd service for prediction API..."
sudo tee /etc/systemd/system/prediction-api.service > /dev/null << 'EOSERVICE'
[Unit]
Description=HPC Resource Prediction API
After=network.target

[Service]
Type=simple
User=ec2-user
WorkingDirectory=/home/ec2-user
Environment="PREDICTION_API_URL=http://localhost:8000"
ExecStart=/usr/bin/python3 /home/ec2-user/learning_api.py
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOSERVICE

echo ""
echo "Starting prediction API..."
sudo systemctl daemon-reload
sudo systemctl enable prediction-api
sudo systemctl start prediction-api

sleep 3

if systemctl is-active --quiet prediction-api; then
    echo "✓ Prediction API is running"
else
    echo "✗ Prediction API failed to start"
    sudo journalctl -u prediction-api -n 20
    exit 1
fi

echo ""
echo "Restarting SLURM controller..."
sudo systemctl restart slurmctld

sleep 2

if systemctl is-active --quiet slurmctld; then
    echo "✓ SLURM controller restarted"
else
    echo "✗ SLURM controller failed to restart"
    sudo journalctl -u slurmctld -n 20
    exit 1
fi

echo ""
echo "════════════════════════════════════════════════════════════"
echo "  Installation Complete!"
echo "════════════════════════════════════════════════════════════"
echo ""
echo "Services:"
echo "  Prediction API: http://localhost:8000"
echo "  Database: ~/data/metrics.db"
echo "  Logs: /var/log/slurmctld.log"
echo ""
echo "Test the API:"
echo "  curl http://localhost:8000/health"
echo "  curl http://localhost:8000/stats"
echo ""
echo "Submit a test job:"
echo "  sbatch --export=DESIGN_NAME=test,DESIGN_GATES=50000 job.sh"
echo ""

EOSSH

echo ""
echo "════════════════════════════════════════════════════════════"
echo "  Deployment Complete!"
echo "════════════════════════════════════════════════════════════"
echo ""
echo "Next steps:"
echo "  1. SSH to head node: ssh ${HEAD_NODE}"
echo "  2. Check API: curl http://localhost:8000/health"
echo "  3. Submit test jobs to start learning"
echo ""
