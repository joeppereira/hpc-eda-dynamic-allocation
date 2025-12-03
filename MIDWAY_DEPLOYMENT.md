# Midway/Isengard Deployment Guide

## Quick Start (30 minutes)

### Step 1: SSH to Cluster (1 min)

```bash
# Midway3
ssh YOUR_CNETID@midway3.rcc.uchicago.edu

# OR Isengard
ssh YOUR_CNETID@isengard.cs.uchicago.edu
```

### Step 2: Setup Environment (5 min)

```bash
# Load modules
module load python/anaconda-2022.05
module load slurm

# Create project directory
mkdir -p ~/hpc-optimization
cd ~/hpc-optimization

# Create virtual environment
python -m venv venv
source venv/bin/activate

# Install dependencies
pip install numpy pandas scikit-learn psutil sqlalchemy fastapi uvicorn
```

### Step 3: Upload Project Files (5 min)

```bash
# On your local machine
cd ~/dynamic_allocation
tar -czf hpc-project.tar.gz \
    database/ monitoring/ prediction/ scripts/ \
    requirements.txt fluent-bit-openroad.conf

# Upload to cluster
scp hpc-project.tar.gz YOUR_CNETID@midway3.rcc.uchicago.edu:~/hpc-optimization/

# Back on cluster
cd ~/hpc-optimization
tar -xzf hpc-project.tar.gz
```

### Step 4: Initialize Database (2 min)

```bash
cd ~/hpc-optimization
python database/schema.py
```

### Step 5: Create SLURM Job Script (5 min)

```bash
cat > submit_openroad.sh <<'EOF'
#!/bin/bash
#SBATCH --job-name=openroad_test
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
#SBATCH --mem=16G
#SBATCH --time=01:00:00
#SBATCH --partition=broadwl
#SBATCH --output=logs/job_%j.out

# Load modules
module load python/anaconda-2022.05
module load singularity

# Design parameters
DESIGN=${1:-gcd}
FREQ=${2:-100}
UTIL=${3:-0.6}

# Run OpenROAD with monitoring
python monitoring/resource_monitor.py \
    --design $DESIGN \
    --freq $FREQ \
    --util $UTIL \
    --output data/metrics/job_${SLURM_JOB_ID}.json
EOF

chmod +x submit_openroad.sh
```

### Step 6: Submit Test Job (2 min)

```bash
# Create directories
mkdir -p logs data/metrics

# Submit job
sbatch submit_openroad.sh gcd 100 0.6

# Check status
squeue -u $USER
sacct
```

### Step 7: Monitor Job (5 min)

```bash
# Watch queue
watch -n 5 squeue -u $USER

# Check output
tail -f logs/job_*.out

# Check metrics
ls -lh data/metrics/
```

### Step 8: Import Data & Train Model (5 min)

```bash
# Import metrics
python scripts/import_metrics.py

# Train model
python prediction/train_model.py

# Evaluate
python scripts/evaluate_model.py
```

---

## Batch Job Submission (Run 20 jobs)

```bash
cat > submit_batch.sh <<'EOF'
#!/bin/bash

DESIGNS=(gcd ibex aes)
FREQS=(100 200 500)
UTILS=(0.5 0.6 0.7)

for design in "${DESIGNS[@]}"; do
    for freq in "${FREQS[@]}"; do
        for util in "${UTILS[@]}"; do
            sbatch submit_openroad.sh $design $freq $util
            echo "Submitted: $design @ ${freq}MHz, ${util} util"
            sleep 1
        done
    done
done
EOF

chmod +x submit_batch.sh
./submit_batch.sh
```

---

## Advantages of Midway/Isengard

✅ **Real SLURM cluster** - Production environment
✅ **No AWS costs** - Free for research
✅ **Already configured** - SLURM ready to use
✅ **Shared filesystem** - Easy data access
✅ **Module system** - Software pre-installed
✅ **Job accounting** - Built-in SLURM accounting

---

## Key Differences from AWS

| Feature | AWS ParallelCluster | Midway/Isengard |
|---------|---------------------|-----------------|
| Setup Time | 1-2 hours | 10 minutes |
| Cost | $500-1500/month | Free |
| SLURM | Need to deploy | Already running |
| SPANK Plugin | Need to compile | Can install |
| Database | Need RDS | Use SQLite or local PostgreSQL |
| OpenROAD | Need to install | Use Singularity container |

---

## Next Steps

Once jobs complete:

1. **Check collected data**
```bash
python -c "
from database.schema import init_database, get_session, Job
engine = init_database('sqlite:///data/metrics.db')
session = get_session(engine)
print(f'Jobs collected: {session.query(Job).count()}')
"
```

2. **Analyze results**
```bash
python scripts/exploratory_analysis.py
python scripts/generate_resource_table.py
```

3. **Deploy prediction API**
```bash
# Start API on login node (or submit as job)
uvicorn prediction.api:app --host 0.0.0.0 --port 8000 &
```

4. **Test optimization**
```bash
python scripts/job_optimizer.py submit_openroad.sh
```

---

## Troubleshooting

### Can't load modules
```bash
# Check available modules
module avail python
module avail slurm

# Load manually
module load python/anaconda-2022.05
```

### SLURM not found
```bash
# Check if SLURM is available
which sbatch
which squeue

# If not, contact cluster admin
```

### Job fails
```bash
# Check job output
cat logs/job_*.out

# Check SLURM logs
sacct -j JOB_ID --format=JobID,State,ExitCode,MaxRSS,Elapsed
```

---

## Estimated Timeline

- **Setup**: 30 minutes
- **Run 20 jobs**: 2-3 hours (parallel execution)
- **Train model**: 5 minutes
- **Deploy API**: 10 minutes
- **Test optimization**: 30 minutes

**Total**: ~4 hours to complete system

---

## Ready to Start?

1. SSH to cluster
2. Run setup commands above
3. Submit test job
4. Monitor and collect data
5. Train model
6. Deploy optimization

**Much faster than AWS deployment!**
