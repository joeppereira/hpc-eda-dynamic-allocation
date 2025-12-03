# File Locations - Learning System Deployment

## Local Development (Your Workspace)

```
your-workspace/
├── slurm/
│   ├── job_submit_learning.lua          # Learning-based plugin
│   └── job_submit_dynamic.lua           # Predictive plugin (old)
│
├── prediction/
│   ├── learning_api.py                  # API with DB queries
│   ├── api.py                           # Original API
│   ├── model.py                         # ML model
│   └── train_model.py                   # Training script
│
├── database/
│   └── schema.py                        # Database schema
│
├── monitoring/
│   └── resource_monitor.py              # Resource monitoring
│
├── scripts/
│   ├── learning_workflow.sh             # Demo workflow
│   └── train_model.py                   # Model training
│
├── aws/
│   └── deploy_learning_system.sh        # Deployment script
│
└── docs/
    ├── LEARNING_SYSTEM.md               # Architecture
    ├── PREDICTIVE_VS_LEARNING.md        # Comparison
    └── DEPLOYMENT_LOCATIONS.md          # This file
```

## AWS Parallel Cluster Deployment

### Head Node (SLURM Controller)

```
/opt/slurm/etc/
├── slurm.conf                           # Add: JobSubmitPlugins=lua
└── job_submit.lua                       # Copy from: slurm/job_submit_learning.lua

/home/ec2-user/
├── learning_api.py                      # Prediction API service
├── model.py                             # ML model code
├── schema.py                            # Database schema
├── data/
│   └── metrics.db                       # SQLite database
├── models/
│   └── resource_predictor.pkl           # Trained model
└── logs/
    └── api.log                          # API logs

/var/log/
└── slurmctld.log                        # Plugin logs here

/etc/systemd/system/
└── prediction-api.service               # API systemd service
```

### Compute Nodes (Optional - for monitoring)

```
/opt/slurm/etc/
└── plugstack.conf                       # SPANK plugin config

/opt/slurm/lib/slurm/
└── spank_monitor.so                     # Monitoring plugin
```

## Installation Commands

### 1. Deploy to AWS (from your local machine)

```bash
# Make deployment script executable
chmod +x aws/deploy_learning_system.sh

# Deploy to cluster
./aws/deploy_learning_system.sh ec2-user@<HEAD_NODE_IP>
```

### 2. Manual Installation (on head node)

```bash
# Copy Lua plugin
sudo cp ~/job_submit_learning.lua /opt/slurm/etc/job_submit.lua
sudo chown slurm:slurm /opt/slurm/etc/job_submit.lua

# Configure SLURM
echo "JobSubmitPlugins=lua" | sudo tee -a /opt/slurm/etc/slurm.conf

# Install Python dependencies
pip3 install fastapi uvicorn sqlalchemy scikit-learn --user

# Initialize database
python3 -c "from schema import init_database; init_database('sqlite:///data/metrics.db')"

# Start API
python3 learning_api.py &

# Restart SLURM
sudo systemctl restart slurmctld
```

## File Purposes

| File | Purpose | Location (Production) |
|------|---------|----------------------|
| `job_submit_learning.lua` | Intercepts job submissions, queries API | `/opt/slurm/etc/job_submit.lua` |
| `learning_api.py` | REST API for predictions | `/home/ec2-user/` (runs as service) |
| `model.py` | ML model implementation | `/home/ec2-user/` |
| `schema.py` | Database schema | `/home/ec2-user/` |
| `metrics.db` | Historical job data | `/home/ec2-user/data/` |
| `resource_predictor.pkl` | Trained model | `/home/ec2-user/models/` |

## Configuration Files

### SLURM Configuration (`/opt/slurm/etc/slurm.conf`)

Add this line:
```
JobSubmitPlugins=lua
```

### API Service (`/etc/systemd/system/prediction-api.service`)

```ini
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

[Install]
WantedBy=multi-user.target
```

### Environment Variables

Set on head node:
```bash
export PREDICTION_API_URL=http://localhost:8000
```

Add to `/etc/environment` for persistence:
```bash
echo "PREDICTION_API_URL=http://localhost:8000" | sudo tee -a /etc/environment
```

## Verification

### Check Plugin Installation

```bash
# On head node
ls -l /opt/slurm/etc/job_submit.lua
grep "JobSubmitPlugins" /opt/slurm/etc/slurm.conf
```

### Check API Service

```bash
# On head node
systemctl status prediction-api
curl http://localhost:8000/health
curl http://localhost:8000/stats
```

### Check Database

```bash
# On head node
sqlite3 ~/data/metrics.db "SELECT COUNT(*) FROM jobs;"
```

### Check Logs

```bash
# Plugin logs
sudo tail -f /var/log/slurmctld.log | grep job_submit

# API logs
journalctl -u prediction-api -f
```

## Troubleshooting

### Plugin Not Loading

```bash
# Check SLURM config
sudo slurmctld -C

# Check Lua syntax
lua -c /opt/slurm/etc/job_submit.lua

# Check logs
sudo grep "job_submit" /var/log/slurm/slurmctld.log
```

### API Not Starting

```bash
# Check service status
systemctl status prediction-api

# Check logs
journalctl -u prediction-api -n 50

# Test manually
python3 ~/learning_api.py
```

### Database Issues

```bash
# Check database exists
ls -l ~/data/metrics.db

# Check schema
sqlite3 ~/data/metrics.db ".schema"

# Reinitialize if needed
python3 -c "from schema import init_database; init_database('sqlite:///data/metrics.db')"
```

## Quick Start Commands

```bash
# Deploy everything
./aws/deploy_learning_system.sh ec2-user@<HEAD_NODE>

# Check status
ssh ec2-user@<HEAD_NODE> "curl http://localhost:8000/health"

# Submit test job
ssh ec2-user@<HEAD_NODE> "sbatch --export=DESIGN_NAME=test,DESIGN_GATES=50000 test.sh"

# Check learning progress
ssh ec2-user@<HEAD_NODE> "curl http://localhost:8000/stats"
```

## Summary

All files are **already saved** in your local workspace. To deploy:

1. Run `./aws/deploy_learning_system.sh ec2-user@<HEAD_NODE>`
2. The script copies files and installs everything
3. System is ready to start learning from job executions

The Lua plugin goes to `/opt/slurm/etc/job_submit.lua` on the head node.
