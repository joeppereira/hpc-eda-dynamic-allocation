#!/bin/bash
# Setup script for head node
# This runs on the head node after cluster creation

set -e

echo "=== Starting head node setup ==="

# Update system
echo "Updating system packages..."
sudo apt-get update -y

# Install dependencies
echo "Installing dependencies..."
sudo apt-get install -y \
    build-essential \
    git \
    wget \
    curl \
    python3-pip \
    python3-dev \
    libpq-dev \
    postgresql-client

# Install Python packages
echo "Installing Python packages..."
pip3 install \
    numpy \
    pandas \
    scikit-learn \
    psutil \
    sqlalchemy \
    psycopg2-binary \
    fastapi \
    uvicorn \
    pydantic \
    matplotlib \
    seaborn \
    pyyaml \
    python-dotenv

# Create project directory
echo "Setting up project directory..."
mkdir -p /shared/hpc-optimization
cd /shared/hpc-optimization

# Clone or copy project files
# (In production, you'd pull from git or S3)
echo "Project files should be copied to /shared/hpc-optimization"

# Create directories
mkdir -p /shared/hpc-optimization/data/metrics
mkdir -p /shared/hpc-optimization/data/results
mkdir -p /shared/hpc-optimization/logs
mkdir -p /shared/config
mkdir -p /shared/spank

# Setup PostgreSQL connection
echo "Setting up database connection..."
cat > /shared/hpc-optimization/.env <<EOF
# Database configuration
DB_HOST=your-rds-endpoint.rds.amazonaws.com
DB_PORT=5432
DB_NAME=hpc_metrics
DB_USER=admin
DB_PASSWORD=your-secure-password

# API configuration
API_HOST=0.0.0.0
API_PORT=8000

# AWS configuration
AWS_REGION=us-east-1
EOF

# Setup prediction API service
echo "Setting up prediction API service..."
sudo cat > /etc/systemd/system/prediction-api.service <<EOF
[Unit]
Description=HPC Resource Prediction API
After=network.target

[Service]
Type=simple
User=ubuntu
WorkingDirectory=/shared/hpc-optimization
Environment="PATH=/usr/local/bin:/usr/bin:/bin"
ExecStart=/usr/local/bin/uvicorn prediction.api:app --host 0.0.0.0 --port 8000
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

# Setup job optimizer service
echo "Setting up job optimizer service..."
sudo cat > /etc/systemd/system/job-optimizer.service <<EOF
[Unit]
Description=SLURM Job Optimizer
After=network.target slurmd.service

[Service]
Type=simple
User=ubuntu
WorkingDirectory=/shared/hpc-optimization
Environment="PATH=/usr/local/bin:/usr/bin:/bin"
ExecStart=/usr/bin/python3 /shared/hpc-optimization/scripts/job_optimizer.py
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

# Reload systemd
sudo systemctl daemon-reload

# Don't start services yet - need to configure database first
echo "Services configured but not started"
echo "After database setup, run:"
echo "  sudo systemctl start prediction-api"
echo "  sudo systemctl start job-optimizer"

# Setup SLURM accounting
echo "Configuring SLURM accounting..."
sudo cat >> /opt/slurm/etc/slurm.conf <<EOF

# Accounting configuration
AccountingStorageType=accounting_storage/slurmdbd
AccountingStorageHost=localhost
AccountingStoragePort=6819
AccountingStorageEnforce=associations,limits,qos
AccountingStoreFlags=job_comment,job_env,job_script

# Job accounting
JobAcctGatherType=jobacct_gather/linux
JobAcctGatherFrequency=30
EOF

# Create Fluent Bit configuration
echo "Creating Fluent Bit configuration..."
cat > /shared/config/fluent-bit.conf <<EOF
[SERVICE]
    Flush        1
    Log_Level    info
    Daemon       off

[INPUT]
    Name         tail
    Path         /shared/logs/openroad_*.log
    Parser       openroad
    Tag          openroad
    Refresh_Interval 1
    
[PARSER]
    Name         openroad
    Format       regex
    Regex        ^\[(?<level>\w+)\]\s+(?<message>.*)$
    
[FILTER]
    Name         grep
    Match        openroad
    Regex        message (Starting|complete|Writing|initialize)
    
[OUTPUT]
    Name         file
    Match        openroad
    Path         /shared/metrics/stage_events
    Format       json
EOF

# Setup cron job for metrics collection
echo "Setting up metrics collection cron job..."
(crontab -l 2>/dev/null; echo "*/5 * * * * /usr/bin/python3 /shared/hpc-optimization/scripts/collect_metrics.py") | crontab -

# Create helper scripts
echo "Creating helper scripts..."
cat > /shared/hpc-optimization/scripts/submit_job.sh <<'EOF'
#!/bin/bash
# Helper script to submit jobs through optimizer

JOB_SCRIPT=$1

if [ -z "$JOB_SCRIPT" ]; then
    echo "Usage: $0 <job_script>"
    exit 1
fi

# Submit through optimizer
python3 /shared/hpc-optimization/scripts/job_optimizer.py submit "$JOB_SCRIPT"
EOF

chmod +x /shared/hpc-optimization/scripts/submit_job.sh

echo "=== Head node setup complete ==="
echo ""
echo "Next steps:"
echo "1. Configure database connection in /shared/hpc-optimization/.env"
echo "2. Initialize database: python3 database/schema.py"
echo "3. Copy project files to /shared/hpc-optimization"
echo "4. Start services:"
echo "   sudo systemctl start prediction-api"
echo "   sudo systemctl start job-optimizer"
echo "5. Test cluster: sbatch test_job.sh"
