# Learning-Based Resource Allocation System

## Overview

This system **learns** from actual job executions to improve resource allocation over time, rather than predicting upfront.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    LEARNING CYCLE                            │
└─────────────────────────────────────────────────────────────┘

First Run (No History):
┌──────────┐    ┌──────────┐    ┌──────────┐    ┌──────────┐
│  User    │───▶│ job_     │───▶│  SLURM   │───▶│  Job     │
│ Submits  │    │ submit   │    │  Queue   │    │  Runs    │
│  Job     │    │ Plugin   │    │          │    │          │
└──────────┘    └──────────┘    └──────────┘    └──────────┘
                      │                                │
                      │ Query API                      │
                      ▼                                ▼
                ┌──────────┐                    ┌──────────┐
                │Prediction│                    │ Monitor  │
                │   API    │                    │ Collects │
                │          │                    │  Metrics │
                │ No data  │                    └──────────┘
                │ → Return │                          │
                │ defaults │                          │
                └──────────┘                          ▼
                                              ┌──────────────┐
                                              │   Database   │
                                              │ Store actual │
                                              │    usage     │
                                              └──────────────┘
                                                      │
                                                      ▼
                                              ┌──────────────┐
                                              │ Train/Update │
                                              │   ML Model   │
                                              └──────────────┘

Subsequent Runs (With History):
┌──────────┐    ┌──────────┐    ┌──────────┐    ┌──────────┐
│  User    │───▶│ job_     │───▶│  SLURM   │───▶│  Job     │
│ Submits  │    │ submit   │    │  Queue   │    │  Runs    │
│  Job     │    │ Plugin   │    │ (adjusted│    │ (optimal │
└──────────┘    └──────────┘    │  --mem)  │    │  memory) │
                      │          └──────────┘    └──────────┘
                      │ Query API                      │
                      ▼                                │
                ┌──────────┐                          │
                │Prediction│                          │
                │   API    │                          │
                │          │                          │
                │ Query DB │                          │
                │ for      │                          │
                │ similar  │                          │
                │ jobs     │                          │
                │          │                          │
                │ Use ML   │                          │
                │ model    │                          │
                │          │                          │
                │ Return   │                          │
                │ learned  │                          │
                │ values   │                          │
                └──────────┘                          │
                      │                                │
                      └────────────────────────────────┘
                            Continues learning
```

## How It Works

### 1. First Job Execution (Cold Start)

```bash
# User submits job
sbatch --mem=4G --export=DESIGN_NAME=aes,DESIGN_GATES=50000 job.sh
```

**What happens:**
1. `job_submit` plugin intercepts submission
2. Queries prediction API: "Do we have data for aes/50k gates?"
3. API responds: "No historical data" → Returns conservative defaults
4. Job runs with defaults (or user-specified resources)
5. **SPANK plugin monitors actual usage** during execution
6. Metrics stored in database: "aes/50k gates used 4.2 GB, 4 cores, 300 sec"

### 2. Model Training

```bash
# Periodic or triggered
python3 scripts/train_model.py
```

**What happens:**
1. Reads all job metrics from database
2. Trains Ridge regression model
3. Learns patterns: "50k gates → ~4GB", "100k gates → ~8GB"
4. Saves model to disk

### 3. Subsequent Job Execution (Warm Start)

```bash
# User submits similar job
sbatch --mem=4G --export=DESIGN_NAME=aes,DESIGN_GATES=55000 job.sh
```

**What happens:**
1. `job_submit` plugin queries API: "aes/55k gates?"
2. API finds similar jobs in database (50k gates)
3. API uses ML model to predict: "55k gates → 4.5 GB"
4. Plugin adjusts: `--mem=4G` → `--mem=5G` (with buffer)
5. Job runs with **learned optimal allocation**
6. Continues monitoring to refine predictions

## Key Components

### 1. job_submit Plugin (`slurm/job_submit_learning.lua`)

- Runs on SLURM head node
- Intercepts job submissions
- Queries prediction API
- Adjusts `--mem` and `--cpus` based on predictions
- Logs all decisions

### 2. Prediction API (`prediction/learning_api.py`)

- FastAPI service
- Queries SQLite database for similar jobs
- Uses ML model for predictions
- Returns confidence levels
- Provides fallback defaults

### 3. Resource Monitor (`monitoring/resource_monitor.py`)

- Runs during job execution (via SPANK or wrapper)
- Collects actual CPU, memory, I/O usage
- Stores metrics in database
- Enables continuous learning

### 4. ML Model (`prediction/model.py`)

- Ridge regression (baseline)
- Features: cell count, frequency, utilization, etc.
- Predicts: memory_gb, cpu_cores, duration_sec
- Trained on historical data

## Advantages Over Predictive Approach

| Aspect | Predictive (Current) | Learning (Proposed) |
|--------|---------------------|---------------------|
| **First run** | Requires formula/heuristic | Uses conservative defaults |
| **Accuracy** | Fixed formula | Improves over time |
| **Adaptability** | Manual updates | Automatic learning |
| **Confidence** | Unknown | Tracked and reported |
| **Data dependency** | None (formula-based) | Requires history |
| **Extrapolation** | Poor | Detects and warns |

## Example Scenario

### Design: AES Cipher, 50,000 gates

**Run 1 (No history):**
```
User request: --mem=4G
Plugin query: No data for aes/50k
Plugin action: Use default (4G)
Actual usage: 4.2 GB
Result: Success, metrics stored
```

**Run 2 (With history):**
```
User request: --mem=4G
Plugin query: Found aes/50k → used 4.2 GB
Plugin action: Adjust to 5G (4.2 * 1.2 buffer)
Actual usage: 4.3 GB
Result: Success, optimal allocation
```

**Run 3 (Larger design):**
```
User request: --mem=4G
Design: aes/100k gates
Plugin query: No exact match, but have 50k data
ML model: Predicts 8.5 GB (scales with size)
Plugin action: Adjust to 10G
Actual usage: 8.7 GB
Result: Success, model learns scaling
```

## Configuration

### 1. Install job_submit Plugin

```bash
# Copy plugin
sudo cp slurm/job_submit_learning.lua /opt/slurm/etc/job_submit.lua

# Configure SLURM
sudo vim /opt/slurm/etc/slurm.conf
# Add: JobSubmitPlugins=lua

# Set API URL
export PREDICTION_API_URL=http://localhost:8000

# Restart SLURM
sudo systemctl restart slurmctld
```

### 2. Start Prediction API

```bash
# Start API
python3 prediction/learning_api.py

# Or with systemd
sudo systemctl start prediction-api
```

### 3. Enable Monitoring

```bash
# Option A: SPANK plugin (production)
sudo cp spank/spank_monitor.so /opt/slurm/lib/slurm/
# Add to plugstack.conf: required /opt/slurm/lib/slurm/spank_monitor.so

# Option B: Wrapper script (testing)
# Wrap jobs with monitoring/resource_monitor.py
```

## Testing

```bash
# Run complete learning workflow
bash scripts/learning_workflow.sh

# This will:
# 1. Submit job with no history (uses defaults)
# 2. Collect actual metrics
# 3. Train model
# 4. Submit similar job (uses learned values)
# 5. Show improvement
```

## Monitoring Learning Progress

```bash
# Check API stats
curl http://localhost:8000/stats

# Query database
sqlite3 data/metrics.db "SELECT COUNT(*) FROM jobs"

# View predictions
curl "http://localhost:8000/predict?design_name=aes&gates=50000&stage=synthesis"
```

## Future Enhancements

1. **Online Learning**: Update model after each job (incremental)
2. **Multi-objective**: Optimize for cost, time, and reliability
3. **Anomaly Detection**: Flag unusual resource usage
4. **Auto-scaling**: Dynamically adjust during execution
5. **Transfer Learning**: Apply knowledge across similar designs

## Summary

This learning-based system:
- ✅ Starts with safe defaults
- ✅ Learns from actual executions
- ✅ Improves accuracy over time
- ✅ Provides confidence metrics
- ✅ Handles new designs gracefully
- ✅ Requires no manual tuning

The system gets smarter with every job execution!
