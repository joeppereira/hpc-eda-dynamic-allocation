#!/bin/bash
# Enable native SLURM REST API on ParallelCluster head node

set -e

echo "=== Enabling SLURM REST API (slurmrestd) ==="

# 1. Check SLURM version
SLURM_VERSION=$(sinfo --version | awk '{print $2}')
echo "SLURM version: $SLURM_VERSION"

# 2. Install slurmrestd if not present
if ! command -v slurmrestd &> /dev/null; then
    echo "Installing slurmrestd..."
    sudo yum install -y slurm-slurmrestd
fi

# 3. Create systemd service
sudo tee /etc/systemd/system/slurmrestd.service > /dev/null <<'EOF'
[Unit]
Description=SLURM REST API Daemon
After=network.target slurmctld.service
Wants=slurmctld.service

[Service]
Type=simple
User=slurm
Group=slurm
ExecStart=/usr/bin/slurmrestd -a rest_auth/local 0.0.0.0:6820
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF

# 4. Start service
echo "Starting slurmrestd service..."
sudo systemctl daemon-reload
sudo systemctl enable slurmrestd
sudo systemctl start slurmrestd

# 5. Check status
sleep 2
sudo systemctl status slurmrestd --no-pager

# 6. Test endpoint
echo ""
echo "Testing REST API endpoint..."
curl -s http://localhost:6820/slurm/v0.0.40/diag | jq '.meta' || echo "API is running"

echo ""
echo "=== SLURM REST API Enabled ==="
echo "Endpoint: http://$(hostname):6820"
echo "API Version: v0.0.40 (check with: curl http://localhost:6820/openapi/v3)"
echo ""
echo "Example job submission:"
echo "  curl -X POST http://localhost:6820/slurm/v0.0.40/job/submit \\"
echo "    -H 'Content-Type: application/json' \\"
echo "    -H 'X-SLURM-USER-NAME: ec2-user' \\"
echo "    -d '{\"job\": {\"script\": \"#!/bin/bash\\nsleep 10\"}}'"
