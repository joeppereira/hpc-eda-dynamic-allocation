# HPC Resource Optimization - Operations Guide

Complete guide for deploying, operating, and maintaining the HPC Resource Optimization system in production.

## Table of Contents

1. [System Overview](#system-overview)
2. [Deployment](#deployment)
3. [Dashboard Operations](#dashboard-operations)
4. [Monitoring & Alerts](#monitoring--alerts)
5. [Maintenance](#maintenance)
6. [Troubleshooting](#troubleshooting)
7. [Performance Tuning](#performance-tuning)

## System Overview

### Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     AWS ParallelCluster                      │
├─────────────────────────────────────────────────────────────┤
│                                                               │
│  ┌──────────────┐      ┌──────────────┐                     │
│  │  SLURM Job   │─────▶│ SPANK Plugin │                     │
│  │  Submission  │      │  (Monitor)   │                     │
│  └──────────────┘      └──────┬───────┘                     │
│                                │                              │
│                                ▼                              │
│                        ┌──────────────┐                      │
│                        │   Database   │                      │
│                        │  (Metrics)   │                      │
│                        └──────┬───────┘                      │
│                                │                              │
│         ┌──────────────────────┼──────────────────────┐     │
│         │                      │                       │     │
│         ▼                      ▼                       ▼     │
│  ┌─────────────┐      ┌──────────────┐      ┌──────────┐   │
│  │  Dashboard  │      │  ML Model    │      │   API    │   │
│  │  (Flask)    │      │  Training    │      │ (FastAPI)│   │
│  └─────────────┘      └──────────────┘      └──────────┘   │
│                                                               │
└─────────────────────────────────────────────────────────────┘
```

### Components

1. **SPANK Plugin**: Real-time resource monitoring
2. **Database**: SQLite/PostgreSQL for metrics storage
3. **ML Model**: Ridge regression for resource prediction
4. **Prediction API**: FastAPI service for real-time predictions
5. **Dashboard**: Flask web interface for visualization
6. **SLURM Integration**: Dynamic resource allocation

## Deployment

### Prerequisites

```bash
# AWS ParallelCluster 3.x
# Python 3.8+
# SLURM 22.x+
# Singularity 3.x+
```

### Initial Setup

#### 1. Deploy Cluster

```bash
# Create cluster
pcluster create-cluster \
  --cluster-name hpc-optimization \
  --cluster-configuration aws/cluster-config.yaml \
  --region us-east-1

# Wait for completion
pcluster describe-cluster \
  --cluster-name hpc-optimization \
  --region us-east-1
```

#### 2. Setup Head Node

```bash
# SSH to head node
pcluster ssh --cluster-name hpc-optimization \
  -i ~/.ssh/eda-cluster-key.pem \
  --region us-east-1

# Create shared directory
sudo mkdir -p /shared/hpc-optimization
sudo chown ec2-user:ec2-user /shared/hpc-optimization

# Upload code
scp -r -i ~/.ssh/eda-cluster-key.pem \
  ./* ec2-user@<head-node-ip>:/shared/hpc-optimization/
```

#### 3. Install Dependencies

```bash
# On head node
cd /shared/hpc-optimization

# Install Python packages
pip3 install --user -r requirements.txt

# Install Singularity (if not in AMI)
sudo yum install -y singularity

# Pull OpenROAD container
singularity pull openroad.sif \
  docker://openroad/flow-ubuntu22.04-builder:latest
```

#### 4. Setup Database

```bash
# Initialize database
python3 database/schema.py

# Verify tables created
sqlite3 /shared/hpc_metrics.db ".tables"
```

#### 5. Compile SPANK Plugin

```bash
cd /shared/hpc-optimization/spank

# Compile plugin
gcc -shared -fPIC -o spank_monitor.so spank_monitor.c \
  -I/usr/include/slurm

# Install plugin
sudo cp spank_monitor.so /usr/lib64/slurm/

# Configure SLURM
sudo bash -c 'echo "required /usr/lib64/slurm/spank_monitor.so" >> /etc/slurm/plugstack.conf'

# Restart SLURM
sudo systemctl restart slurmctld
```

#### 6. Start Services

```bash
# Start prediction API
cd /shared/hpc-optimization
nohup python3 prediction/api.py > api.log 2>&1 &

# Start dashboard
cd /shared/hpc-optimization/dashboard
nohup python3 app.py > dashboard.log 2>&1 &

# Verify services
curl http://localhost:8000/health
curl http://localhost:5000/api/stats/summary
```

### Production Deployment

#### Using Systemd Services

```bash
# Copy service files
sudo cp dashboard/dashboard.service /etc/systemd/system/
sudo cp prediction/prediction-api.service /etc/systemd/system/

# Enable and start services
sudo systemctl enable dashboard prediction-api
sudo systemctl start dashboard prediction-api

# Check status
sudo systemctl status dashboard
sudo systemctl status prediction-api
```

## Dashboard Operations

### Accessing Dashboard

```bash
# Get head node IP
HEAD_NODE_IP=$(pcluster describe-cluster \
  --cluster-name hpc-optimization \
  --region us-east-1 \
  --query 'headNode.publicIpAddress' \
  --output text)

# Access dashboard
echo "Dashboard: http://$HEAD_NODE_IP:5000"
```

### Dashboard Features

#### 1. Summary Statistics
- **Total Jobs**: Jobs in last 24 hours
- **CPU Savings**: Percentage reduction
- **Memory Savings**: Percentage reduction
- **Cost Savings**: Dollar amount saved

#### 2. Resource Allocation Chart
- **Red bars**: Initial requested resources
- **Orange bars**: Actual usage (SPANK)
- **Green bars**: ML predicted (optimized)

#### 3. Cost Savings Timeline
- CPU savings trend
- Memory savings trend
- Historical performance

#### 4. Design Correlation
- Gates vs CPU usage
- Nets vs memory usage
- Complexity analysis

#### 5. Recent Jobs Table
- Job details
- Resource comparison
- Savings metrics
- Status tracking

### Using the Dashboard

#### Monitor Active Jobs

```bash
# View in dashboard
# Navigate to: http://<head-node-ip>:5000

# Or via API
curl http://localhost:5000/api/jobs/recent | jq '.'
```

#### Check Optimization Performance

```bash
# Get summary stats
curl http://localhost:5000/api/stats/summary | jq '.'

# Expected output:
{
  "total_jobs": 150,
  "cpu_savings_percent": 45.2,
  "memory_savings_percent": 42.8,
  "cost_savings": 56.75,
  "cost_savings_percent": 45.2
}
```

#### Analyze Specific Job

```bash
# Get job details
curl http://localhost:5000/api/jobs/12345 | jq '.'

# View SPANK timeline
curl http://localhost:5000/api/jobs/12345 | jq '.spank_timeline'
```

## Monitoring & Alerts

### Key Metrics

#### 1. Prediction Accuracy
```bash
# Check model accuracy
python3 scripts/evaluate_model.py

# Target: >80% accuracy
# Alert if: <70% accuracy
```

#### 2. Resource Savings
```bash
# Check savings rate
curl http://localhost:5000/api/stats/summary | \
  jq '.cpu_savings_percent, .memory_savings_percent'

# Target: 30-50% savings
# Alert if: <20% savings
```

#### 3. Job Success Rate
```bash
# Check job completion
sacct -S now-1day --format=JobID,State | \
  grep -c COMPLETED

# Target: >95% success
# Alert if: <90% success
```

#### 4. System Health
```bash
# Check services
systemctl status dashboard prediction-api

# Check logs
tail -f /shared/hpc-optimization/dashboard/dashboard.log
tail -f /shared/hpc-optimization/api.log
```

### Setting Up Alerts

#### CloudWatch Integration

```bash
# Install CloudWatch agent
sudo yum install -y amazon-cloudwatch-agent

# Configure metrics
cat > /opt/aws/amazon-cloudwatch-agent/etc/config.json << 'EOF'
{
  "metrics": {
    "namespace": "HPC/Optimization",
    "metrics_collected": {
      "cpu": {
        "measurement": [
          {"name": "cpu_usage_idle", "rename": "CPU_IDLE"}
        ]
      },
      "mem": {
        "measurement": [
          {"name": "mem_used_percent", "rename": "MEM_USED"}
        ]
      }
    }
  }
}
EOF

# Start agent
sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
  -a fetch-config \
  -m ec2 \
  -s \
  -c file:/opt/aws/amazon-cloudwatch-agent/etc/config.json
```

#### Email Alerts

```python
# Add to dashboard/app.py
import smtplib
from email.mime.text import MIMEText

def send_alert(subject, message):
    msg = MIMEText(message)
    msg['Subject'] = subject
    msg['From'] = 'alerts@example.com'
    msg['To'] = 'ops@example.com'
    
    s = smtplib.SMTP('localhost')
    s.send_message(msg)
    s.quit()

# Check thresholds
@app.route('/api/check_alerts')
def check_alerts():
    stats = get_summary_stats()
    
    if stats['cpu_savings_percent'] < 20:
        send_alert(
            "Low Optimization Rate",
            f"CPU savings only {stats['cpu_savings_percent']:.1f}%"
        )
    
    return jsonify({"status": "checked"})
```

## Maintenance

### Daily Tasks

```bash
# Check system health
systemctl status dashboard prediction-api

# Review logs
tail -100 /shared/hpc-optimization/dashboard/dashboard.log

# Check disk space
df -h /shared

# Verify database
sqlite3 /shared/hpc_metrics.db "SELECT COUNT(*) FROM job_metrics;"
```

### Weekly Tasks

```bash
# Retrain ML model
cd /shared/hpc-optimization
python3 prediction/train_model.py

# Backup database
cp /shared/hpc_metrics.db \
   /shared/backups/hpc_metrics_$(date +%Y%m%d).db

# Clean old logs
find /shared/hpc-optimization -name "*.log" -mtime +30 -delete

# Update statistics
python3 scripts/generate_weekly_report.py
```

### Monthly Tasks

```bash
# Archive old data
python3 scripts/archive_old_metrics.py --days 90

# Review cost savings
python3 scripts/cost_analysis.py --month $(date +%Y-%m)

# Update documentation
# Review and update operational procedures

# Security updates
sudo yum update -y
```

### Model Retraining

```bash
# Check if retraining needed
python3 scripts/evaluate_model.py

# If accuracy < 80%, retrain
python3 prediction/train_model.py

# Validate new model
python3 scripts/evaluate_model.py --model prediction/ridge_model.pkl

# Deploy new model (automatic if validation passes)
```

## Troubleshooting

### Dashboard Not Accessible

```bash
# Check if service is running
systemctl status dashboard

# Check port is open
netstat -tlnp | grep 5000

# Check firewall
sudo iptables -L -n | grep 5000

# Restart service
sudo systemctl restart dashboard

# Check logs
tail -f /shared/hpc-optimization/dashboard/dashboard.log
```

### No Data in Dashboard

```bash
# Check database has data
sqlite3 /shared/hpc_metrics.db \
  "SELECT COUNT(*) FROM job_metrics;"

# Check SPANK plugin is running
grep spank_monitor /var/log/slurm/slurmctld.log

# Submit test job
sbatch scripts/test_job.sh

# Verify data collection
sqlite3 /shared/hpc_metrics.db \
  "SELECT * FROM job_metrics ORDER BY timestamp DESC LIMIT 1;"
```

### Predictions Not Working

```bash
# Check API is running
curl http://localhost:8000/health

# Test prediction
curl -X POST http://localhost:8000/predict \
  -H "Content-Type: application/json" \
  -d '{"num_gates": 5000, "num_nets": 4500}'

# Check model file exists
ls -lh prediction/ridge_model.pkl

# Retrain if needed
python3 prediction/train_model.py
```

### SPANK Plugin Issues

```bash
# Check plugin is loaded
scontrol show config | grep PlugStackConfig

# Check plugin file
ls -lh /usr/lib64/slurm/spank_monitor.so

# Check SLURM logs
tail -f /var/log/slurm/slurmctld.log | grep spank

# Recompile if needed
cd /shared/hpc-optimization/spank
gcc -shared -fPIC -o spank_monitor.so spank_monitor.c \
  -I/usr/include/slurm
sudo cp spank_monitor.so /usr/lib64/slurm/
sudo systemctl restart slurmctld
```

## Performance Tuning

### Database Optimization

```bash
# Add indexes
sqlite3 /shared/hpc_metrics.db << 'EOF'
CREATE INDEX IF NOT EXISTS idx_timestamp ON job_metrics(timestamp);
CREATE INDEX IF NOT EXISTS idx_job_id ON job_metrics(job_id);
CREATE INDEX IF NOT EXISTS idx_design ON job_metrics(design_name);
EOF

# Vacuum database
sqlite3 /shared/hpc_metrics.db "VACUUM;"

# Analyze for query optimization
sqlite3 /shared/hpc_metrics.db "ANALYZE;"
```

### Dashboard Performance

```python
# Add caching to app.py
from flask_caching import Cache

cache = Cache(app, config={'CACHE_TYPE': 'simple'})

@app.route('/api/stats/summary')
@cache.cached(timeout=60)  # Cache for 60 seconds
def get_summary_stats():
    # ... existing code ...
```

### API Performance

```python
# Use connection pooling in api.py
from sqlalchemy.pool import QueuePool

engine = create_engine(
    'sqlite:///hpc_metrics.db',
    poolclass=QueuePool,
    pool_size=10,
    max_overflow=20
)
```

## Cost Analysis

### Current vs Optimized

```bash
# Generate cost report
python3 << 'EOF'
import sqlite3

conn = sqlite3.connect('/shared/hpc_metrics.db')
cursor = conn.cursor()

cursor.execute('''
    SELECT 
        COUNT(*) as jobs,
        AVG(requested_cpu) as avg_req_cpu,
        AVG(predicted_cpu) as avg_pred_cpu,
        AVG(requested_memory_mb) as avg_req_mem,
        AVG(predicted_memory_mb) as avg_pred_mem
    FROM job_metrics
    WHERE timestamp > datetime('now', '-30 days')
''')

row = cursor.fetchone()
jobs, req_cpu, pred_cpu, req_mem, pred_mem = row

# c5.xlarge: $0.17/hour
cost_per_cpu_hour = 0.0425
cost_per_gb_hour = 0.02125

current_cost = (req_cpu / 100) * cost_per_cpu_hour * jobs
optimized_cost = (pred_cpu / 100) * cost_per_cpu_hour * jobs
savings = current_cost - optimized_cost

print(f"30-Day Analysis:")
print(f"  Jobs: {jobs}")
print(f"  Current Cost: ${current_cost:.2f}")
print(f"  Optimized Cost: ${optimized_cost:.2f}")
print(f"  Savings: ${savings:.2f} ({savings/current_cost*100:.1f}%)")
print(f"  Annual Projection: ${savings * 12:.2f}")

conn.close()
EOF
```

## Backup & Recovery

### Database Backup

```bash
# Daily backup
0 2 * * * cp /shared/hpc_metrics.db /shared/backups/hpc_metrics_$(date +\%Y\%m\%d).db

# Weekly backup to S3
0 3 * * 0 aws s3 cp /shared/hpc_metrics.db s3://my-bucket/backups/hpc_metrics_$(date +\%Y\%m\%d).db
```

### Recovery

```bash
# Restore from backup
cp /shared/backups/hpc_metrics_20251111.db /shared/hpc_metrics.db

# Restart services
sudo systemctl restart dashboard prediction-api

# Verify
curl http://localhost:5000/api/stats/summary
```

## Security

### Access Control

```bash
# Restrict dashboard access
# Add to app.py
from flask_httpauth import HTTPBasicAuth

auth = HTTPBasicAuth()

@auth.verify_password
def verify_password(username, password):
    # Implement authentication
    return username == 'admin' and password == 'secure_password'

@app.route('/')
@auth.login_required
def index():
    return render_template('dashboard.html')
```

### SSL/TLS

```bash
# Generate certificate
openssl req -x509 -newkey rsa:4096 \
  -keyout key.pem -out cert.pem \
  -days 365 -nodes

# Run with SSL
python3 app.py --cert cert.pem --key key.pem
```

## Support & Documentation

- **GitHub**: [project-repo]
- **Wiki**: [project-repo]/wiki
- **Issues**: [project-repo]/issues
- **Email**: support@example.com

## Appendix

### Useful Commands

```bash
# Check cluster status
pcluster describe-cluster --cluster-name hpc-optimization --region us-east-1

# View SLURM queue
squeue

# View job history
sacct -S now-1day

# Check compute nodes
sinfo

# View job details
scontrol show job <job_id>

# Cancel job
scancel <job_id>

# Hold/release job
scontrol hold <job_id>
scontrol release <job_id>
```

### Configuration Files

- Cluster: `aws/cluster-config.yaml`
- SPANK: `/etc/slurm/plugstack.conf`
- Dashboard: `dashboard/app.py`
- API: `prediction/api.py`
- Database: `database/schema.py`
