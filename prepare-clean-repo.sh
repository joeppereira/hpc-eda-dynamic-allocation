#!/bin/bash
# Prepare clean repository with only essential operational files

set -e

CLEAN_DIR="dynamic_allocation_clean"

echo "=========================================="
echo "Preparing Clean Repository"
echo "=========================================="
echo ""

# Remove old clean directory if exists
rm -rf $CLEAN_DIR

# Create clean directory structure
mkdir -p $CLEAN_DIR/{dashboard/templates,monitoring,database,prediction,spank,aws/scripts,scripts,data/{metrics,temp,results},.kiro/steering}

echo "✓ Created directory structure"

# Copy essential files
echo ""
echo "Copying essential files..."

# Root files
cp README.md $CLEAN_DIR/
cp requirements.txt $CLEAN_DIR/
cp .gitignore $CLEAN_DIR/
cp OPERATIONS_GUIDE.md $CLEAN_DIR/

# Dashboard (complete)
cp dashboard/app.py $CLEAN_DIR/dashboard/
cp dashboard/README.md $CLEAN_DIR/dashboard/
cp dashboard/templates/dashboard.html $CLEAN_DIR/dashboard/templates/
cp dashboard/dashboard.service $CLEAN_DIR/dashboard/
cp dashboard/__init__.py $CLEAN_DIR/dashboard/

# Monitoring
cp monitoring/resource_monitor.py $CLEAN_DIR/monitoring/
cp monitoring/openroad_log_parser.py $CLEAN_DIR/monitoring/

# Database
cp database/schema.py $CLEAN_DIR/database/

# Prediction/ML
cp prediction/model.py $CLEAN_DIR/prediction/
cp prediction/train_model.py $CLEAN_DIR/prediction/
cp prediction/api.py $CLEAN_DIR/prediction/

# SPANK Plugin
cp spank/spank_monitor.c $CLEAN_DIR/spank/

# AWS ParallelCluster
cp aws/cluster-config.yaml $CLEAN_DIR/aws/
cp aws/DEPLOYMENT_GUIDE.md $CLEAN_DIR/aws/
cp aws/SLURM_BEST_PRACTICES.md $CLEAN_DIR/aws/
cp aws/deploy.sh $CLEAN_DIR/aws/
cp aws/scripts/setup-head-node.sh $CLEAN_DIR/aws/scripts/

# Essential scripts
cp scripts/generate_sample_data.py $CLEAN_DIR/scripts/
cp scripts/simulate_openroad_job.py $CLEAN_DIR/scripts/
cp scripts/run_openroad_with_monitoring.py $CLEAN_DIR/scripts/
cp scripts/evaluate_model.py $CLEAN_DIR/scripts/

# Demo scripts
cp demo-dashboard.sh $CLEAN_DIR/
cp push-to-gitlab.sh $CLEAN_DIR/

# Data placeholders
touch $CLEAN_DIR/data/metrics/.gitkeep
touch $CLEAN_DIR/data/temp/.gitkeep
touch $CLEAN_DIR/data/results/.gitkeep

# Steering (optional but useful)
cp .kiro/steering/project-setup.md $CLEAN_DIR/.kiro/steering/

echo "✓ Copied all essential files"

# Create file list
echo ""
echo "Creating file inventory..."
cat > $CLEAN_DIR/FILE_INVENTORY.md << 'EOF'
# File Inventory

## Essential Operational Files

### Core Components

#### Dashboard (Web Interface)
- `dashboard/app.py` - Flask application backend
- `dashboard/templates/dashboard.html` - Web UI
- `dashboard/README.md` - Dashboard documentation
- `dashboard/dashboard.service` - Systemd service file

#### Monitoring
- `monitoring/resource_monitor.py` - Python resource monitoring
- `monitoring/openroad_log_parser.py` - Log parsing utilities

#### Database
- `database/schema.py` - SQLAlchemy schema definitions

#### ML Prediction
- `prediction/model.py` - Ridge regression model
- `prediction/train_model.py` - Model training script
- `prediction/api.py` - FastAPI prediction service

#### SPANK Plugin
- `spank/spank_monitor.c` - SLURM SPANK plugin for real-time monitoring

### AWS ParallelCluster

#### Configuration
- `aws/cluster-config.yaml` - ParallelCluster configuration
- `aws/deploy.sh` - Deployment automation script
- `aws/scripts/setup-head-node.sh` - Head node setup

#### Documentation
- `aws/DEPLOYMENT_GUIDE.md` - Complete deployment guide
- `aws/SLURM_BEST_PRACTICES.md` - SLURM optimization guide

### Scripts

#### Operational
- `scripts/generate_sample_data.py` - Generate demo data
- `scripts/simulate_openroad_job.py` - Job simulation
- `scripts/run_openroad_with_monitoring.py` - Monitored job execution
- `scripts/evaluate_model.py` - Model evaluation

#### Demo
- `demo-dashboard.sh` - Quick dashboard demo
- `push-to-gitlab.sh` - GitLab push helper

### Documentation
- `README.md` - Project overview and quick start
- `OPERATIONS_GUIDE.md` - Complete operations manual
- `requirements.txt` - Python dependencies

### Configuration
- `.gitignore` - Git ignore rules
- `.kiro/steering/project-setup.md` - Project context

## File Count by Category

- Dashboard: 5 files
- Monitoring: 2 files
- Database: 1 file
- Prediction: 3 files
- SPANK: 1 file
- AWS: 5 files
- Scripts: 4 files
- Documentation: 3 files
- Configuration: 2 files

**Total: 26 essential files**

## Excluded Files

The following were excluded as non-essential for operations:

- Exploratory analysis scripts
- Historical documentation files
- Temporary status files
- Development checkpoints
- Multiple deployment variations
- Embedded repositories
- Build artifacts

## Usage

All files are production-ready and documented. See:
- `README.md` for quick start
- `OPERATIONS_GUIDE.md` for detailed operations
- Individual component READMEs for specific features
EOF

echo "✓ Created file inventory"

# Show summary
echo ""
echo "=========================================="
echo "✓ Clean Repository Ready"
echo "=========================================="
echo ""
echo "Location: $CLEAN_DIR/"
echo ""
echo "File count:"
find $CLEAN_DIR -type f -not -path '*/\.*' | wc -l | xargs echo "  Total files:"
echo ""
echo "Directory structure:"
tree -L 2 $CLEAN_DIR 2>/dev/null || find $CLEAN_DIR -type d | head -20
echo ""
echo "Next steps:"
echo "  1. Review files: cd $CLEAN_DIR"
echo "  2. Initialize git: cd $CLEAN_DIR && git init"
echo "  3. Commit: git add -A && git commit -m 'Initial commit'"
echo "  4. Push: git remote add origin https://gitlab.aws.dev/spereirj/dynamic_allocation.git"
echo "  5. Push: git push -u origin main"
echo ""
