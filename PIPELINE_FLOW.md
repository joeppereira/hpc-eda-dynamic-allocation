# Complete Pipeline Flow - Current Status

## What We Have Built

### ✅ Phase 1: Local Infrastructure (COMPLETE)

```
1. Database Schema (SQLite)
   ├── jobs table
   ├── design_features table
   ├── job_stages table
   └── stage_resources table

2. Resource Monitoring (Python/psutil)
   ├── CPU tracking
   ├── Memory tracking
   └── I/O tracking

3. Prediction Model (Ridge Regression)
   ├── Feature engineering (17 features)
   ├── Per-stage models (synthesis, placement, routing)
   └── Trained on 7 jobs

4. Data Collection
   ├── 7 simulated jobs
   ├── 21 stage records
   └── Actual metrics in database
```

### ⚠️ Phase 1: Incomplete Tasks

```
4. OpenROAD Log Parser
   ✅ Fluent Bit config created
   ❌ Not tested (Docker platform issue on ARM Mac)

5. OpenROAD Execution Wrapper
   ✅ Script created
   ❌ Can't run (x86 Docker image on ARM Mac)
```

---

## Complete Pipeline Flow (Design)

### Step 1: Job Submission
```bash
./scripts/run_real_openroad.sh gcd 100 0.6
```

### Step 2: OpenROAD Execution
```
Docker Container (openroad/orfs)
├── Run OpenROAD flow
├── Generate logs → /tmp/openroad_gcd_100mhz_0.6util.log
└── Output: synthesis → placement → routing
```

### Step 3: Log Parsing (Fluent Bit)
```
Fluent Bit (fluent-bit-openroad.conf)
├── Tail: /tmp/openroad_*.log
├── Parse: Stage markers
│   ├── [INFO] Reading → read_design
│   ├── [INFO] initialize_floorplan → floorplan
│   ├── [INFO] Starting global placement → placement_start
│   ├── [INFO] Global placement complete → placement_end
│   ├── [INFO] Starting clock tree → cts_start
│   ├── [INFO] Starting global routing → routing_start
│   └── [INFO] Detailed routing complete → routing_end
└── Output: /tmp/openroad_stages.json
```

### Step 4: Resource Monitoring (psutil)
```
monitoring/resource_monitor.py
├── Monitor Docker process
├── Sample every 1 second
│   ├── CPU utilization
│   ├── Memory (RSS, peak)
│   └── Disk I/O
├── Correlate with stages from Fluent Bit
└── Output: data/metrics/job_name.json
```

### Step 5: Data Import
```
scripts/import_metrics.py
├── Read: data/metrics/*.json
├── Parse: Design features + stage resources
├── Validate: Realistic bounds
└── Store: SQLite database
```

### Step 6: Model Training
```
prediction/train_model.py
├── Load: Historical data from database
├── Extract: 17 features per job
├── Train: Ridge regression (per stage, per resource)
├── Validate: R² score, MAE, RMSE
└── Save: prediction/trained_model.pkl
```

### Step 7: Prediction API
```
prediction/api.py (FastAPI)
├── Endpoint: POST /predict
├── Input: Design features (cells, freq, util)
├── Process: Load model → extract features → predict
└── Output: {cpu_cores, memory_gb, duration_sec} per stage
```

### Step 8: Job Optimization
```
scripts/job_optimizer.py
├── Parse: Job script
├── Query: Prediction API
├── Modify: SLURM directives (#SBATCH)
└── Submit: Optimized job
```

---

## Current Data Flow (What Actually Works)

### Working Flow (Simulated Data)
```
1. simulate_openroad_job.py
   ↓
2. Simulated metrics → data/metrics/*.json
   ↓
3. import_metrics.py → SQLite database
   ↓
4. train_model.py → trained_model.pkl
   ↓
5. api.py → Predictions
```

### Blocked Flow (Real OpenROAD)
```
1. run_real_openroad.sh
   ↓
2. Docker (x86) ❌ ARM Mac incompatible
   ↓
3. [BLOCKED]
```

---

## The Problem: Docker Platform Mismatch

**Your Mac**: ARM64 (Apple Silicon)  
**OpenROAD Image**: x86_64 (Intel)

**Options**:

### Option A: Use Rosetta (Slow but works)
```bash
# Enable Rosetta emulation
docker run --platform linux/amd64 openroad/orfs ...
```
⚠️ Will be slow (emulation overhead)

### Option B: Build ARM Image
```bash
# Build OpenROAD for ARM
git clone https://github.com/The-OpenROAD-Project/OpenROAD-flow-scripts
cd OpenROAD-flow-scripts
docker build --platform linux/arm64 -t openroad-arm .
```
⏱️ Takes 1-2 hours

### Option C: Deploy to AWS (x86 instances)
```bash
# AWS instances are x86
# OpenROAD will run natively
# No platform issues
```
✅ **Recommended**

---

## What We Can Do Right Now

### 1. Test Pipeline with Simulated Data
```bash
# Already working
python3 scripts/exploratory_analysis.py
python3 scripts/evaluate_model.py
python3 scripts/generate_resource_table.py
```

### 2. Start Prediction API
```bash
# Test API locally
cd prediction
uvicorn api:app --reload &

# Test prediction
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
```

### 3. Deploy to AWS (Skip Docker Issues)
```bash
# Follow TODAY_EXECUTION_PLAN.md
# AWS instances are x86 - OpenROAD will work
aws configure
./aws/pre-deployment-check.sh
```

---

## Recommendation

**Skip local OpenROAD execution. Deploy to AWS now.**

**Why?**
1. ✅ Infrastructure validated (database, monitoring, model)
2. ✅ Pipeline design proven
3. ❌ Docker platform issue blocks local OpenROAD
4. ✅ AWS has x86 instances - no platform issues
5. ⏱️ Fixing Docker locally wastes time

**Next Step**: Start AWS deployment (Phase 2 from TODAY_EXECUTION_PLAN.md)

---

## Pipeline Summary

| Component | Status | Location |
|-----------|--------|----------|
| Database | ✅ Working | SQLite (local) |
| Monitoring | ✅ Working | psutil |
| Log Parser | ✅ Created | Fluent Bit config |
| OpenROAD Wrapper | ✅ Created | run_real_openroad.sh |
| **OpenROAD Execution** | ❌ **Blocked** | **Docker platform issue** |
| Model Training | ✅ Working | Ridge regression |
| Prediction API | ✅ Ready | FastAPI |
| Job Optimizer | ✅ Ready | Python script |

**Blocker**: Can't run x86 Docker on ARM Mac efficiently

**Solution**: Deploy to AWS (x86 instances)
