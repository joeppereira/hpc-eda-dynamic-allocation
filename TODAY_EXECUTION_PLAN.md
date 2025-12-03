# TODAY's Execution Plan - Complete Implementation

**Goal**: Deploy complete HPC Resource Optimization system to AWS in ONE DAY

**Timeline**: 8-10 hours total (with parallel tasks)

---

## Phase 1: AWS Setup (1 hour) - START NOW

### Hour 1: Infrastructure Deployment (9:00 AM - 10:00 AM)

**Tasks (parallel where possible):**

```bash
# Terminal 1: AWS Setup
aws configure  # 2 min
./aws/pre-deployment-check.sh  # 1 min

# Get AWS IDs
aws ec2 describe-vpcs --query 'Vpcs[*].[VpcId,IsDefault]' --output table
aws ec2 describe-subnets --query 'Subnets[*].[SubnetId,AvailabilityZone]' --output table
aws ec2 create-key-pair --key-name hpc-key --query 'KeyMaterial' --output text > ~/.ssh/hpc-key.pem
chmod 400 ~/.ssh/hpc-key.pem

# Create S3 bucket
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
aws s3 mb s3://hpc-optimization-$ACCOUNT_ID
aws s3 cp aws/scripts/ s3://hpc-optimization-$ACCOUNT_ID/scripts/ --recursive

# Update cluster config (5 min)
# Edit aws/cluster-config.yaml with your subnet IDs and key name

# Deploy cluster (15 min wait)
pcluster create-cluster --cluster-name hpc-opt --cluster-configuration aws/cluster-config.yaml

# Terminal 2: While cluster deploys, create RDS
aws rds create-db-instance \
    --db-instance-identifier hpc-metrics \
    --db-instance-class db.t3.small \
    --engine postgres \
    --master-username admin \
    --master-user-password YourSecurePass123! \
    --allocated-storage 100

# Monitor both
watch -n 30 'pcluster describe-cluster --cluster-name hpc-opt --query clusterStatus'
```

**Deliverable**: Cluster + RDS deploying (15-20 min wait time)

---

## Phase 2: Cluster Setup (1 hour) - 10:00 AM - 11:00 AM

### While Waiting for Cluster

```bash
# Prepare project files for upload
tar -czf hpc-project.tar.gz \
    database/ monitoring/ prediction/ scripts/ \
    requirements.txt spank/

# Compile SPANK plugin locally
cd spank
make
cd ..

# Test prediction API locally
python3 prediction/api.py &
curl http://localhost:8000/health
```

### Once Cluster is Ready

```bash
# SSH to head node
pcluster ssh --cluster-name hpc-opt -i ~/.ssh/hpc-key.pem

# On head node:
# Upload project
scp -i ~/.ssh/hpc-key.pem hpc-project.tar.gz ubuntu@HEAD_NODE_IP:/home/ubuntu/
ssh -i ~/.ssh/hpc-key.pem ubuntu@HEAD_NODE_IP

# Extract and setup
tar -xzf hpc-project.tar.gz
cd /shared
mkdir -p hpc-optimization
cp -r ~/database ~/monitoring ~/prediction ~/scripts /shared/hpc-optimization/

# Install dependencies
pip3 install -r /shared/hpc-optimization/requirements.txt

# Setup database connection
cat > /shared/hpc-optimization/.env <<EOF
DB_HOST=hpc-metrics.XXXXX.rds.amazonaws.com
DB_PORT=5432
DB_NAME=postgres
DB_USER=admin
DB_PASSWORD=YourSecurePass123!
EOF

# Initialize database
cd /shared/hpc-optimization
python3 database/schema.py
```

**Deliverable**: Cluster ready, database initialized

---

## Phase 3: Data Collection (3 hours) - 11:00 AM - 2:00 PM

### Prepare Test Designs (30 min)

```bash
# On head node
cd /shared/openroad

# Download test designs
git clone https://github.com/The-OpenROAD-Project/OpenROAD-flow-scripts.git
cd OpenROAD-flow-scripts

# Or use pre-built designs
# Download Ibex, AES, JPEG designs
```

### Create Job Submission Script (15 min)

```bash
cat > /shared/submit_openroad_job.sh <<'EOF'
#!/bin/bash
#SBATCH --job-name=openroad_{DESIGN}_{FREQ}_{UTIL}
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
#SBATCH --mem=16G
#SBATCH --time=01:00:00
#SBATCH --output=/shared/logs/job_%j.out

# Design features for SPANK plugin
export DESIGN_CELL_COUNT={CELLS}
export DESIGN_NET_COUNT={NETS}
export DESIGN_DIE_AREA={AREA}
export DESIGN_UTIL={UTIL}
export DESIGN_FREQ_MHZ={FREQ}
export DESIGN_TECH_NODE=130

# Run OpenROAD with monitoring
python3 /shared/hpc-optimization/monitoring/resource_monitor.py \
    --design {DESIGN} \
    --freq {FREQ} \
    --util {UTIL} \
    --output /shared/metrics/job_$SLURM_JOB_ID.json
EOF
```

### Submit 50 Jobs (2 hours runtime)

```bash
# Create job matrix
cat > submit_all_jobs.sh <<'EOF'
#!/bin/bash

DESIGNS=("small:5000" "medium:20000" "large:50000" "xlarge:100000")
FREQS=(100 200 500)
UTILS=(0.5 0.6 0.7)

for design_spec in "${DESIGNS[@]}"; do
    IFS=':' read -r design cells <<< "$design_spec"
    for freq in "${FREQS[@]}"; do
        for util in "${UTILS[@]}"; do
            # Substitute values and submit
            sed -e "s/{DESIGN}/$design/g" \
                -e "s/{CELLS}/$cells/g" \
                -e "s/{FREQ}/$freq/g" \
                -e "s/{UTIL}/$util/g" \
                /shared/submit_openroad_job.sh > /tmp/job_${design}_${freq}_${util}.sh
            
            sbatch /tmp/job_${design}_${freq}_${util}.sh
            echo "Submitted: $design @ ${freq}MHz, ${util} util"
        done
    done
done
EOF

chmod +x submit_all_jobs.sh
./submit_all_jobs.sh

# Monitor progress
watch -n 10 'squeue; echo ""; sacct -S today'
```

**Deliverable**: 36-50 jobs submitted and running (2 hours to complete)

---

## Phase 4: Model Training (30 min) - 2:00 PM - 2:30 PM

### While Jobs Run, Prepare Training Pipeline

```bash
# Import completed jobs continuously
cat > /shared/import_loop.sh <<'EOF'
#!/bin/bash
while true; do
    python3 /shared/hpc-optimization/scripts/import_metrics.py
    sleep 60
done
EOF

chmod +x /shared/import_loop.sh
nohup ./import_loop.sh > /tmp/import.log 2>&1 &
```

### Once 20+ Jobs Complete

```bash
# Check database
python3 -c "
from database.schema import init_database, get_session, Job
engine = init_database('postgresql://admin:PASS@ENDPOINT:5432/postgres')
session = get_session(engine)
count = session.query(Job).count()
print(f'Jobs in database: {count}')
"

# Train model
cd /shared/hpc-optimization
python3 prediction/train_model.py

# Evaluate
python3 scripts/evaluate_model.py

# Generate resource table
python3 scripts/generate_resource_table.py
```

**Deliverable**: Model trained on 20+ real jobs

---

## Phase 5: Prediction API Deployment (30 min) - 2:30 PM - 3:00 PM

```bash
# Start prediction API
cd /shared/hpc-optimization
nohup uvicorn prediction.api:app --host 0.0.0.0 --port 8000 > /tmp/api.log 2>&1 &

# Test API
curl http://localhost:8000/health
curl -X POST http://localhost:8000/predict \
    -H "Content-Type: application/json" \
    -d '{
        "cell_count": 50000,
        "net_count": 45000,
        "die_area_um2": 10000000,
        "utilization_target": 0.7,
        "clock_freq_mhz": 500,
        "technology_node_nm": 130
    }'

# Setup as systemd service
sudo systemctl start prediction-api
sudo systemctl enable prediction-api
```

**Deliverable**: Prediction API running and tested

---

## Phase 6: Dynamic Optimization (1 hour) - 3:00 PM - 4:00 PM

### Implement Job Optimizer

```bash
cat > /shared/hpc-optimization/scripts/job_optimizer.py <<'EOF'
#!/usr/bin/env python3
import sys
import re
import requests

def optimize_job(job_script_path):
    # Parse job script
    with open(job_script_path) as f:
        content = f.read()
    
    # Extract design features
    cell_count = int(re.search(r'DESIGN_CELL_COUNT=(\d+)', content).group(1))
    freq_mhz = int(re.search(r'DESIGN_FREQ_MHZ=(\d+)', content).group(1))
    util = float(re.search(r'DESIGN_UTIL=([\d.]+)', content).group(1))
    
    # Query prediction API
    response = requests.post('http://localhost:8000/predict', json={
        'cell_count': cell_count,
        'net_count': int(cell_count * 0.9),
        'die_area_um2': cell_count * 200,
        'utilization_target': util,
        'clock_freq_mhz': freq_mhz,
        'technology_node_nm': 130
    })
    
    predictions = response.json()
    
    # Calculate total resources
    max_memory = max(p['memory_gb'] for p in predictions)
    total_duration = sum(p['duration_sec'] for p in predictions)
    max_cpus = max(p['cpu_cores'] for p in predictions)
    
    # Add 20% buffer
    opt_memory = int(max_memory * 1.2)
    opt_time = int(total_duration * 1.2 / 60)  # minutes
    opt_cpus = int(max_cpus)
    
    # Modify SBATCH directives
    content = re.sub(r'#SBATCH --mem=\d+G', f'#SBATCH --mem={opt_memory}G', content)
    content = re.sub(r'#SBATCH --time=\d+:\d+:\d+', f'#SBATCH --time=00:{opt_time:02d}:00', content)
    content = re.sub(r'#SBATCH --cpus-per-task=\d+', f'#SBATCH --cpus-per-task={opt_cpus}', content)
    
    # Save optimized script
    opt_path = job_script_path.replace('.sh', '_optimized.sh')
    with open(opt_path, 'w') as f:
        f.write(content)
    
    print(f"Optimized: {opt_cpus} CPUs, {opt_memory}GB RAM, {opt_time} min")
    return opt_path

if __name__ == '__main__':
    optimize_job(sys.argv[1])
EOF

chmod +x /shared/hpc-optimization/scripts/job_optimizer.py
```

### Test Optimization

```bash
# Create test job
cp /shared/submit_openroad_job.sh /tmp/test_job.sh

# Optimize it
python3 /shared/hpc-optimization/scripts/job_optimizer.py /tmp/test_job.sh

# Submit optimized job
sbatch /tmp/test_job_optimized.sh
```

**Deliverable**: Job optimizer working

---

## Phase 7: Validation (2 hours) - 4:00 PM - 6:00 PM

### Submit Optimized Jobs

```bash
# Submit 20 optimized jobs
for i in {1..20}; do
    # Create job
    sed -e "s/{DESIGN}/test$i/g" \
        -e "s/{CELLS}/50000/g" \
        -e "s/{FREQ}/500/g" \
        -e "s/{UTIL}/0.7/g" \
        /shared/submit_openroad_job.sh > /tmp/job_$i.sh
    
    # Optimize
    python3 /shared/hpc-optimization/scripts/job_optimizer.py /tmp/job_$i.sh
    
    # Submit
    sbatch /tmp/job_${i}_optimized.sh
done

# Wait for completion
watch -n 30 'squeue'
```

### Generate Final Report

```bash
# Once jobs complete
python3 /shared/hpc-optimization/scripts/compare_efficiency.py

# Generate comprehensive analysis
python3 /shared/hpc-optimization/scripts/generate_resource_table.py

# Create final report
python3 /shared/hpc-optimization/scripts/final_report.py
```

**Deliverable**: Efficiency comparison, final metrics

---

## Timeline Summary

| Time | Phase | Duration | Tasks |
|------|-------|----------|-------|
| 9:00 AM | AWS Setup | 1 hour | Deploy cluster, RDS |
| 10:00 AM | Cluster Setup | 1 hour | Configure, install deps |
| 11:00 AM | Data Collection | 3 hours | Submit 50 jobs, collect metrics |
| 2:00 PM | Model Training | 30 min | Train on 20+ jobs |
| 2:30 PM | API Deployment | 30 min | Deploy prediction API |
| 3:00 PM | Optimization | 1 hour | Implement job optimizer |
| 4:00 PM | Validation | 2 hours | Test optimized jobs |
| 6:00 PM | **COMPLETE** | - | System operational |

**Total: 9 hours**

---

## Parallel Execution Strategy

### Terminal 1: AWS Infrastructure
```bash
# Deploy cluster (background)
pcluster create-cluster ...
# Deploy RDS (background)
aws rds create-db-instance ...
```

### Terminal 2: Local Preparation
```bash
# Compile SPANK plugin
# Package project files
# Test components locally
```

### Terminal 3: Job Monitoring
```bash
# Watch job queue
watch -n 10 squeue
# Monitor metrics collection
tail -f /shared/metrics/*.json
```

### Terminal 4: Model Training
```bash
# Continuous import
./import_loop.sh
# Train as data arrives
python3 prediction/train_model.py
```

---

## Critical Path

**Must complete in order:**
1. AWS Setup (1 hour) - BLOCKING
2. Cluster Setup (1 hour) - BLOCKING
3. Data Collection (3 hours) - BLOCKING for model
4. Model Training (30 min) - BLOCKING for API
5. API + Optimization (1.5 hours) - Can parallelize
6. Validation (2 hours) - Final step

**Minimum time**: 8 hours (if everything works perfectly)
**Realistic time**: 9-10 hours (with debugging)

---

## Risk Mitigation

### If Cluster Deploy Fails (15 min delay)
- Use default VPC
- Try different region
- Use smaller instance types

### If Jobs Fail (30 min delay)
- Check SLURM logs
- Reduce job complexity
- Use simpler designs

### If Model Accuracy Low (<85%)
- Collect more jobs (add 1 hour)
- Adjust hyperparameters
- Use ensemble model

### If Time Runs Out
**Minimum Viable Product (6 hours)**:
- Cluster deployed ✓
- 20 jobs collected ✓
- Model trained ✓
- Predictions working ✓
- Skip: Full optimization, extensive validation

---

## Success Criteria (End of Day)

- [ ] AWS Cluster operational
- [ ] 50+ jobs collected
- [ ] Model trained (R² > 0.85)
- [ ] Prediction API deployed
- [ ] Job optimizer working
- [ ] Efficiency improvement > 15%
- [ ] Complete documentation

---

## START NOW!

```bash
# First command to run:
aws configure

# Then:
./aws/pre-deployment-check.sh

# Then follow Phase 1 above
```

**Let's do this! 🚀**
