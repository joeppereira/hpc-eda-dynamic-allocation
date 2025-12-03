# Design Document

## Overview

The HPC Resource Optimization System creates a multi-dimensional mapping to predict resource requirements for HPC/EDA workloads:

```
f(Design Features, Tool Config, Stage) → Resource Requirements + Bottlenecks
```

The system consists of:
1. **SPANK Plugin** - Monitors job execution and captures per-stage metrics
2. **Log Processor** - Detects stages from tool output in real-time
3. **Metrics Database** - Stores historical execution data
4. **Prediction Engine** - ML models trained on historical data
5. **Job Optimizer** - Modifies SLURM submissions based on predictions

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                  AWS Parallel Cluster                    │
│  ┌────────────────────────────────────────────────────┐ │
│  │              SLURM Scheduler                       │ │
│  │  ┌──────────────────────────────────────────────┐ │ │
│  │  │         SPANK Plugin                         │ │ │
│  │  │  - Job lifecycle hooks                       │ │ │
│  │  │  - Resource monitoring                       │ │ │
│  │  │  - Metrics collection                        │ │ │
│  │  └──────────────────────────────────────────────┘ │ │
│  │  ┌──────────────────────────────────────────────┐ │ │
│  │  │         Log Processor (Fluent Bit)           │ │ │
│  │  │  - Real-time log tailing                     │ │ │
│  │  │  - Stage detection via regex                 │ │ │
│  │  │  - Local processing (privacy)                │ │ │
│  │  └──────────────────────────────────────────────┘ │ │
│  └────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────┘
                          │
                          ▼
              ┌───────────────────────┐
              │  Metrics Database     │
              │  (PostgreSQL/RDS)     │
              │  - Job metadata       │
              │  - Design features    │
              │  - Stage resources    │
              └───────────────────────┘
                          │
                          ▼
              ┌───────────────────────┐
              │  Prediction Engine    │
              │  (Ridge Regression)   │
              │  - Per-stage models   │
              │  - Feature engineering│
              └───────────────────────┘
                          │
                          ▼
              ┌───────────────────────┐
              │  Job Optimizer        │
              │  (Python Service)     │
              │  - Intercept jobs     │
              │  - Query predictions  │
              │  - Modify resources   │
              └───────────────────────┘
```

## Components and Interfaces

### 1. SPANK Plugin

**Technology:** C (compiled shared library)

**Purpose:** Monitor SLURM jobs and capture per-stage resource metrics

**Key Functions:**
- `slurm_spank_init()` - Initialize plugin, read configuration
- `slurm_spank_job_prolog()` - Before job starts, capture design metadata
- `slurm_spank_task_post_fork()` - After task fork, start monitoring thread
- `slurm_spank_task_exit()` - Task completion, finalize metrics
- `slurm_spank_job_epilog()` - After job ends, export metrics

**Monitoring Thread:**
```c
void* monitor_thread(void* arg) {
    while (job_running) {
        // Sample every 1 second
        collect_cpu_metrics();      // /proc/[pid]/stat
        collect_memory_metrics();   // /proc/[pid]/status
        collect_io_metrics();       // /proc/[pid]/io
        
        // Get current stage from log processor
        current_stage = get_current_stage();
        
        // Associate metrics with stage
        store_stage_metrics(current_stage, metrics);
        
        sleep(1);
    }
}
```

**Output Format:**
```json
{
  "job_id": "12345",
  "job_name": "openroad_placement_test",
  "start_time": "2025-11-10T10:00:00Z",
  "end_time": "2025-11-10T11:30:00Z",
  "design_features": {
    "cell_count": 500000,
    "net_count": 450000,
    "die_area_um2": 10000000,
    "utilization": 0.70,
    "clock_freq_mhz": 500
  },
  "stages": [
    {
      "stage_name": "placement",
      "start_time": "2025-11-10T10:15:00Z",
      "end_time": "2025-11-10T11:05:00Z",
      "duration_sec": 3000,
      "cpu_util_avg": 85.3,
      "cpu_util_peak": 98.1,
      "memory_peak_gb": 42.5,
      "disk_read_gb": 2.1,
      "disk_write_gb": 1.8,
      "bottleneck": "memory"
    }
  ]
}
```

### 2. Log Processor (Fluent Bit)

**Technology:** Fluent Bit (C-based, lightweight)

**Purpose:** Real-time stage detection from tool logs

**Why Fluent Bit:**
- Memory footprint: 1-2MB (vs Fluentd's 40-100MB)
- CPU overhead: 0.5-1%
- Latency: <50ms
- Local processing (data privacy)
- Built-in tail with inotify
- Production-ready

**Configuration:**
```yaml
# fluent-bit.conf
[SERVICE]
    Flush        1
    Log_Level    info

[INPUT]
    Name         tail
    Path         /tmp/openroad_*.log
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
    Regex        message (Starting|complete|Writing)
    
[OUTPUT]
    Name         file
    Match        openroad
    Path         /tmp/stage_events
    Format       json
```

**Stage Detection Patterns:**
```
[INFO] Reading LEF file          → read_design
[INFO] initialize_floorplan      → floorplan
[INFO] Starting global placement → placement_start
[INFO] Global placement complete → placement_end
[INFO] Starting clock tree       → cts_start
[INFO] Starting global routing   → routing_start
[INFO] Detailed routing complete → routing_end
[INFO] Writing DEF               → finishing
```

### 3. Metrics Database

**Technology:** PostgreSQL (RDS for production, SQLite for local testing)

**Why Custom Database vs SLURM Accounting:**

SLURM has built-in accounting (`slurmdbd`) that tracks job-level metrics, but it's insufficient for our needs:

| Feature | SLURM Accounting | Custom Database | Why We Need Custom |
|---------|------------------|-----------------|-------------------|
| Job-level metrics | ✅ CPU time, memory | ✅ Same | Both provide this |
| **Per-stage metrics** | ❌ Job aggregate only | ✅ Placement, routing, etc. | **Core requirement** - predict per stage |
| **Design features** | ❌ Can't store | ✅ Cell count, frequency, etc. | **Essential** - ML features |
| **Stage detection** | ❌ No concept of stages | ✅ Stage boundaries from logs | **Required** - correlate resources with stages |
| Custom queries | ⚠️ Limited | ✅ Full SQL | **Needed** - feature extraction for ML |
| Cost | Free (included) | $0 local, $25/month AWS | Minimal cost for critical capability |

**Example: What SLURM Can't Do**

SLURM accounting shows:
```
JobID: 12345, CPUTime: 02:30:00, MaxRSS: 42.5GB
```

We need:
```
JobID: 12345, Stage: placement, CellCount: 500K, Freq: 500MHz
  → Memory: 42.5GB, Duration: 3000s, Bottleneck: memory
JobID: 12345, Stage: routing, CellCount: 500K, Freq: 500MHz
  → Memory: 38.2GB, Duration: 2400s, Bottleneck: compute
```

**Hybrid Approach (Recommended):**
- **SLURM accounting** - Enable for basic job tracking and debugging (free)
- **Custom database** - Store per-stage metrics and design features (required for ML)

**Schema:**

```sql
-- Job metadata
CREATE TABLE jobs (
    job_id VARCHAR(64) PRIMARY KEY,
    job_name VARCHAR(256),
    workload_type VARCHAR(32),  -- 'EDA' or 'HPC'
    tool_name VARCHAR(64),      -- 'openroad', 'yosys', etc.
    submit_time TIMESTAMP,
    start_time TIMESTAMP,
    end_time TIMESTAMP,
    status VARCHAR(32),
    exit_code INTEGER
);

-- Design features (EDA-specific)
CREATE TABLE design_features (
    job_id VARCHAR(64) REFERENCES jobs(job_id),
    cell_count INTEGER,
    net_count INTEGER,
    die_area_um2 BIGINT,
    utilization_target FLOAT,
    aspect_ratio FLOAT,
    clock_freq_mhz FLOAT,
    clock_domains INTEGER,
    technology_node_nm INTEGER,
    metal_layers INTEGER,
    hierarchy_depth INTEGER,
    PRIMARY KEY (job_id)
);

-- Job stages
CREATE TABLE job_stages (
    stage_id SERIAL PRIMARY KEY,
    job_id VARCHAR(64) REFERENCES jobs(job_id),
    stage_name VARCHAR(64),
    stage_order INTEGER,
    start_time TIMESTAMP,
    end_time TIMESTAMP,
    duration_sec INTEGER
);

-- Per-stage resource metrics
CREATE TABLE stage_resources (
    stage_id INTEGER REFERENCES job_stages(stage_id),
    timestamp TIMESTAMP,
    cpu_util_pct FLOAT,
    cpu_cores_used INTEGER,
    memory_rss_gb FLOAT,
    memory_peak_gb FLOAT,
    disk_read_gb FLOAT,
    disk_write_gb FLOAT,
    bottleneck_type VARCHAR(32),  -- 'compute', 'memory', 'io'
    PRIMARY KEY (stage_id, timestamp)
);

-- Tool configurations
CREATE TABLE tool_configs (
    job_id VARCHAR(64) REFERENCES jobs(job_id),
    config_json JSONB,  -- Flexible storage for tool-specific params
    PRIMARY KEY (job_id)
);
```

**Key Queries:**

```sql
-- Get average resources for similar designs
SELECT AVG(sr.memory_peak_gb), AVG(js.duration_sec)
FROM stage_resources sr
JOIN job_stages js ON sr.stage_id = js.stage_id
JOIN design_features df ON js.job_id = df.job_id
WHERE js.stage_name = 'placement'
  AND df.cell_count BETWEEN 450000 AND 550000
  AND df.utilization_target BETWEEN 0.65 AND 0.75;

-- Analyze bottlenecks by stage
SELECT stage_name, bottleneck_type, COUNT(*) as frequency
FROM stage_resources sr
JOIN job_stages js ON sr.stage_id = js.stage_id
GROUP BY stage_name, bottleneck_type
ORDER BY frequency DESC;
```

### 4. Prediction Engine

**Technology:** scikit-learn (Ridge Regression)

**Model Architecture:**

```python
from sklearn.linear_model import Ridge
from sklearn.preprocessing import StandardScaler
from sklearn.pipeline import Pipeline

# Separate model per stage and resource type
models = {
    'placement': {
        'cpu_cores': Pipeline([
            ('scaler', StandardScaler()),
            ('regressor', Ridge(alpha=1.0))
        ]),
        'memory_gb': Pipeline([
            ('scaler', StandardScaler()),
            ('regressor', Ridge(alpha=1.0))
        ]),
        'duration_sec': Pipeline([
            ('scaler', StandardScaler()),
            ('regressor', Ridge(alpha=1.0))
        ])
    },
    'routing': {
        # Similar structure
    }
    # ... per stage
}
```

**Feature Engineering:**

```python
def extract_features(design_config):
    """Extract and normalize features for model input"""
    return {
        # Log-transformed for scale
        'log_cell_count': np.log1p(design_config['cell_count']),
        'log_net_count': np.log1p(design_config['net_count']),
        'log_die_area': np.log1p(design_config['die_area_um2']),
        
        # Normalized features
        'utilization': design_config['utilization_target'],
        'aspect_ratio': design_config['aspect_ratio'],
        'clock_freq_ghz': design_config['clock_freq_mhz'] / 1000.0,
        'tech_node_normalized': design_config['technology_node_nm'] / 130.0,
        
        # Derived features
        'cell_density': design_config['cell_count'] / design_config['die_area_um2'],
        'net_to_cell_ratio': design_config['net_count'] / design_config['cell_count'],
        'complexity_score': design_config['clock_freq_mhz'] * design_config['cell_count'] / 1e6
    }
```

**API Interface:**

```python
from fastapi import FastAPI
from pydantic import BaseModel

app = FastAPI()

class DesignFeatures(BaseModel):
    cell_count: int
    net_count: int
    die_area_um2: int
    utilization_target: float
    clock_freq_mhz: float
    technology_node_nm: int

class ResourcePrediction(BaseModel):
    stage_name: str
    cpu_cores: int
    memory_gb: float
    duration_sec: float
    confidence: float

@app.post("/predict", response_model=List[ResourcePrediction])
def predict_resources(features: DesignFeatures):
    """Predict resource requirements for all stages"""
    feature_vector = extract_features(features.dict())
    
    predictions = []
    for stage_name, stage_models in models.items():
        pred = ResourcePrediction(
            stage_name=stage_name,
            cpu_cores=int(stage_models['cpu_cores'].predict([feature_vector])[0]),
            memory_gb=float(stage_models['memory_gb'].predict([feature_vector])[0]),
            duration_sec=float(stage_models['duration_sec'].predict([feature_vector])[0]),
            confidence=0.85  # From validation metrics
        )
        predictions.append(pred)
    
    return predictions
```

### 5. Job Optimizer

**Technology:** Python service

**Purpose:** Intercept SLURM job submissions and modify resource allocations

**Workflow:**

```python
def optimize_job(job_script_path):
    """
    1. Parse job script to extract design features
    2. Query prediction API
    3. Modify SLURM directives
    4. Submit optimized job
    """
    # Parse job script
    design_features = parse_job_script(job_script_path)
    
    # Query prediction API
    response = requests.post(
        "http://prediction-api:8000/predict",
        json=design_features
    )
    predictions = response.json()
    
    # Calculate total resources needed
    total_memory = max(p['memory_gb'] for p in predictions)
    total_duration = sum(p['duration_sec'] for p in predictions)
    cpu_cores = max(p['cpu_cores'] for p in predictions)
    
    # Modify SLURM directives
    modify_slurm_directives(
        job_script_path,
        mem=f"{int(total_memory * 1.1)}G",  # 10% buffer
        time=f"{int(total_duration * 1.2 / 60)}",  # 20% buffer in minutes
        cpus=cpu_cores
    )
    
    # Submit job
    job_id = submit_job(job_script_path)
    
    # Track for validation
    track_prediction(job_id, predictions)
    
    return job_id
```

## Data Models

### Design Features
```python
@dataclass
class DesignFeatures:
    cell_count: int
    net_count: int
    die_area_um2: int
    utilization_target: float
    aspect_ratio: float
    clock_freq_mhz: float
    clock_domains: int
    technology_node_nm: int
    metal_layers: int
    hierarchy_depth: int
```

### Stage Metrics
```python
@dataclass
class StageMetrics:
    stage_name: str
    start_time: datetime
    end_time: datetime
    duration_sec: int
    cpu_util_avg: float
    cpu_util_peak: float
    memory_peak_gb: float
    disk_read_gb: float
    disk_write_gb: float
    bottleneck_type: str  # 'compute', 'memory', 'io', 'dependency'
```

### Resource Prediction
```python
@dataclass
class ResourcePrediction:
    stage_name: str
    cpu_cores: int
    memory_gb: float
    duration_sec: float
    confidence: float
```

## Error Handling

### SPANK Plugin Errors
- **Plugin load failure**: Log to syslog, SLURM continues without monitoring
- **Monitoring thread crash**: Catch signals, export partial metrics
- **Disk full**: Buffer metrics in memory, export when space available
- **Process tracking lost**: Re-scan process tree, log gap in metrics

### Log Processor Errors
- **Log file not found**: Wait for file creation (inotify)
- **Regex match failure**: Log unmatched lines for analysis
- **Stage detection timeout**: Use heuristics based on elapsed time
- **Fluent Bit crash**: Systemd auto-restart, minimal data loss

### Database Errors
- **Connection failure**: Retry with exponential backoff
- **Duplicate job_id**: Update existing record (idempotent)
- **Schema validation failure**: Log error, skip record
- **Query timeout**: Use connection pooling, optimize indexes

### Prediction API Errors
- **Model not loaded**: Return 503 Service Unavailable
- **Invalid input features**: Return 400 Bad Request with validation errors
- **Prediction out of bounds**: Clamp to realistic ranges, log warning
- **API timeout**: Use async processing for batch predictions

### Job Optimizer Errors
- **Prediction API unavailable**: Fall back to conservative defaults
- **Job script parse failure**: Submit original job unmodified
- **SLURM submission failure**: Retry with original resources
- **Under-allocation detected**: Alert operators, increase buffer percentage

## Testing Strategy

### Unit Tests
- SPANK plugin functions (mocked SLURM API)
- Log parser regex patterns
- Feature extraction logic
- Model prediction accuracy
- Database queries

### Integration Tests
- SPANK plugin on test SLURM cluster
- Fluent Bit with sample OpenROAD logs
- End-to-end: job submission → monitoring → database → prediction
- API load testing (concurrent requests)

### System Tests
- Full cluster deployment
- Baseline vs optimized job comparison
- Prediction accuracy validation
- Efficiency improvement measurement

### Performance Tests
- SPANK plugin overhead (<2% CPU)
- Log processing latency (<100ms)
- Prediction API response time (<100ms)
- Database query performance

## Deployment Strategy

### Phase 1: Local Development (Your Laptop/Workstation)

**Purpose:** Develop and test components before cloud deployment

**Hardware Requirements:**
- CPU: 4+ cores (for running OpenROAD in Docker)
- RAM: 16GB minimum (OpenROAD can use 8-12GB for medium designs)
- Disk: 50GB free space (for Docker images, PDKs, test data)
- OS: macOS, Linux, or WSL2 on Windows

**Components Running Locally:**
1. **SQLite database** - Lightweight file-based database for testing
2. **Docker** - Runs OpenROAD container
3. **Python monitoring script** - Simulates SPANK plugin functionality using psutil
4. **Log parser** - Python script to detect stages from OpenROAD logs
5. **Prediction API** - FastAPI running on localhost:8000
6. **Test scripts** - Execute 5-10 small OpenROAD jobs

**What's NOT running locally:**
- No real SLURM cluster (not needed for initial development)
- No real SPANK plugin (use Python simulation)
- No Fluent Bit (use Python log parser)

**Local Development Flow:**
```
Your Laptop
├── Docker (OpenROAD)
├── Python monitoring script (psutil)
├── Log parser (Python)
├── SQLite database
├── Prediction model training
└── FastAPI prediction service
```

**Cost:** $0 (all local)

---

### Phase 2: AWS Parallel Cluster (Cloud Deployment)

**Purpose:** Production deployment with real SLURM and SPANK plugin

**AWS Resources Required:**

**1. Head Node (Always Running)**
- Instance: c5.xlarge (4 vCPU, 8GB RAM)
- Purpose: SLURM controller, job submission, prediction API
- Cost: ~$0.17/hour = ~$122/month

**2. Compute Nodes (Auto-scaling)**
- Instance: c5.4xlarge (16 vCPU, 32GB RAM) - for OpenROAD jobs
- Count: 2-10 nodes (scales based on queue)
- Purpose: Run OpenROAD jobs with SPANK monitoring
- Cost: ~$0.68/hour per node
  - 2 nodes × 8 hours/day × 20 days = ~$218/month
  - 10 nodes × 8 hours/day × 20 days = ~$1,088/month

**3. Database (Always Running)**
- RDS PostgreSQL: db.t3.small (2 vCPU, 2GB RAM)
- Storage: 100GB SSD
- Purpose: Store per-stage metrics, design features, predictions
- Why not SLURM accounting: Need per-stage data and design features (see design section)
- Cost: ~$0.034/hour = ~$25/month (~0.3% of total AWS cost)
- Note: Also enable SLURM accounting (free) for basic job tracking

**4. Shared Storage**
- Amazon EFS or FSx for Lustre: 500GB
- Purpose: Shared filesystem for OpenROAD, PDKs, job data
- Cost: ~$150/month (EFS Standard)

**5. Data Transfer**
- Minimal (all processing within VPC)
- Cost: ~$10/month

**Total AWS Cost Estimate:**
- **Minimal usage** (2 nodes, 8 hours/day): ~$525/month
- **Moderate usage** (5 nodes, 8 hours/day): ~$850/month
- **Heavy usage** (10 nodes, 8 hours/day): ~$1,395/month

**AWS Architecture:**
```
AWS Cloud
├── VPC
│   ├── Head Node (c5.xlarge)
│   │   ├── SLURM controller
│   │   ├── Prediction API
│   │   └── Job optimizer
│   ├── Compute Nodes (c5.4xlarge × 2-10, auto-scaling)
│   │   ├── SLURM compute daemons
│   │   ├── SPANK plugin
│   │   ├── Fluent Bit
│   │   └── OpenROAD + PDKs
│   ├── RDS PostgreSQL (db.t3.small)
│   └── EFS/FSx (shared storage)
└── CloudWatch (monitoring)
```

---

### Deployment Phases Summary

| Phase | Where | Hardware | Cost | Purpose |
|-------|-------|----------|------|---------|
| **Phase 1: Local Dev** | Your laptop | 4+ cores, 16GB RAM | $0 | Develop components, test with 5-10 jobs |
| **Phase 2: AWS Staging** | AWS Parallel Cluster | 1 head + 2 compute nodes | ~$525/month | Test SPANK plugin, collect 50-100 jobs |
| **Phase 3: AWS Production** | AWS Parallel Cluster | 1 head + 5-10 compute nodes | ~$850-1,395/month | Production workloads, continuous optimization |

---

### Recommended Approach

**Week 1-2: Local Development (Your Laptop)**
- Develop all Python components
- Test with Docker OpenROAD
- Train initial models on 5-10 local jobs
- **Cost: $0**

**Week 3-4: AWS Deployment (Cloud)**
- Deploy small cluster (2 compute nodes)
- Implement real SPANK plugin
- Collect 50-100 production jobs
- Retrain models on real data
- **Cost: ~$525 for 1 month**

**Week 5+: Production (Cloud)**
- Scale to 5-10 compute nodes
- Enable dynamic optimization
- Continuous monitoring and retraining
- **Cost: ~$850-1,395/month**

---

### Cost Optimization Tips

1. **Use Spot Instances** for compute nodes (50-70% savings)
2. **Auto-scaling** - nodes only run when jobs are queued
3. **Scheduled shutdown** - turn off cluster nights/weekends if not needed
4. **Reserved Instances** - 1-year commitment saves 30-40%
5. **Right-sizing** - start with smaller instances, scale up if needed

**With Spot Instances + Auto-scaling:**
- Staging: ~$300/month
- Production: ~$500-800/month

## Security Considerations

- **Data Privacy**: All log processing happens on compute nodes, no external transmission
- **Access Control**: Database credentials stored in AWS Secrets Manager
- **API Authentication**: JWT tokens for prediction API access
- **SLURM Integration**: Job optimizer runs as trusted service account
- **Audit Logging**: All job modifications logged for compliance
