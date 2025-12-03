---
title: HPC Resource Optimization with SLURM and SPANK Plugin
status: draft
---

# Overview

Build an end-to-end system for AWS Parallel Cluster that:
1. Runs HPC workloads with SLURM scheduling
2. Captures resource usage at each job stage using SPANK plugin
3. Predicts optimal resource allocation for future jobs
4. Dynamically adjusts resources based on historical data

# Execution Plan

## Local End-to-End Validation
**Goal**: Validate complete flow locally with REAL OpenROAD before cluster deployment

**CRITICAL REQUIREMENT**: Must use REAL OpenROAD execution, not simulated/mock data

### Tasks

1. **Environment Setup** (30 min)
   - [ ] Install OpenROAD locally (Docker: `docker pull openroad/flow-ubuntu`)
   - [ ] OR: Install OpenROAD-flow-scripts from source
   - [ ] Install SkyWater 130nm PDK
   - [ ] Set up Python environment (scikit-learn, pandas, psutil)
   - [ ] Verify OpenROAD installation: `openroad -version`

2. **Real OpenROAD Stage Detection** (2-3 hours)
   - [ ] **MUST**: Parse actual OpenROAD log files to detect stages
   - [ ] Identify stage markers in OpenROAD output:
     - Read design: `[INFO] Reading LEF/DEF/Liberty`
     - Floorplan: `[INFO] initialize_floorplan`
     - Placement: `[INFO] Starting global placement` → `[INFO] Global placement complete`
     - CTS: `[INFO] Starting clock tree synthesis`
     - Routing: `[INFO] Starting global routing` → `[INFO] Detailed routing complete`
     - Finishing: `[INFO] Writing DEF/GDS`
   - [ ] Create log parser to extract stage boundaries with timestamps
   - [ ] Extract design features from logs (cell count, net count, die area, utilization)

3. **Resource Monitoring Integration** (2 hours)
   - [ ] Create Python monitoring script using psutil
   - [ ] Monitor OpenROAD process and children
   - [ ] Capture per-stage metrics:
     - CPU utilization (average, peak)
     - Memory usage (RSS, peak)
     - Disk I/O (read/write bytes)
     - Duration (start/end timestamps)
   - [ ] Associate metrics with detected stages
   - [ ] Output structured JSON format

4. **Test Design Preparation** (1 hour)
   - [ ] Download open-source designs:
     - Ibex RISC-V core (~5K cells)
     - AES encryption (~20K cells)
     - JPEG encoder (~50K cells)
   - [ ] Prepare OpenROAD flow scripts for each design
   - [ ] Create design variation matrix:
     - Clock frequencies: 100MHz, 200MHz, 500MHz
     - Utilization targets: 50%, 60%, 70%
     - Technology nodes: 130nm (SkyWater), 45nm (ASAP7 if available)

5. **REAL Data Collection** (2-3 hours)
   - [ ] **MUST**: Run actual OpenROAD flow (not simulation)
   - [ ] Execute 5-10 real jobs with design variations
   - [ ] Monitor each job with resource tracking
   - [ ] Parse OpenROAD logs to extract stage information
   - [ ] Validate data quality:
     - All stages detected correctly
     - Resource metrics captured for each stage
     - Design features extracted from logs
   - [ ] Store metrics in JSON format

6. **Database & Model** (2-3 hours)
   - [ ] Create SQLite database schema
   - [ ] Import REAL collected metrics (not mock data)
   - [ ] Verify data integrity:
     - Stage names match OpenROAD stages
     - Resource values are realistic
     - Design features correlate with resource usage
   - [ ] Implement Ridge regression model
   - [ ] Train on real OpenROAD data
   - [ ] Validate predictions against held-out real jobs

7. **Prediction API** (1-2 hours)
   - [ ] Build FastAPI service
   - [ ] Endpoint: POST /predict with design features
   - [ ] Returns: predicted CPU, memory, duration per stage
   - [ ] Test with real design parameters
   - [ ] Validate predictions match actual OpenROAD behavior

**Deliverable**: Working pipeline trained on REAL OpenROAD data that can accurately predict resources for actual designs

**Success Criteria**:
- ✅ OpenROAD actually runs (not simulated)
- ✅ All OpenROAD stages detected from logs
- ✅ Real resource metrics captured per stage
- ✅ Model trained on real data
- ✅ Predictions validated against actual runs

## Parallel Cluster Deployment
**Goal**: Deploy to production cluster and validate with live workloads

### Tasks
1. **Cluster Setup**
   - Deploy AWS Parallel Cluster
   - Configure SLURM
   - Install OpenROAD on cluster
   - Deploy SPANK plugin

2. **Production Data Collection**
   - Submit 20-50 jobs with variations
   - Monitor SPANK plugin
   - Collect metrics to RDS/PostgreSQL

3. **Model Retraining**
   - Retrain on production data
   - Validate accuracy
   - Deploy prediction API

4. **Dynamic Allocation Testing**
   - Implement job optimizer
   - Submit optimized jobs
   - Compare efficiency
   - Generate report

**Deliverable**: Production system with efficiency improvements demonstrated

# Requirements

## 0. CRITICAL: Real Workload Execution (NOT Simulation)

**MANDATORY REQUIREMENT**: The system MUST use actual workload execution, not mock/simulated data.

### Why Real Execution is Required

**Problem with Mock Data:**
- ❌ Simulated workloads don't reflect real tool behavior
- ❌ Synthetic resource patterns don't match actual EDA/HPC tools
- ❌ Cannot accurately predict real job requirements
- ❌ Model trained on fake data is useless for production

**Real Execution Requirements:**
- ✅ Run actual OpenROAD binary on real designs
- ✅ Parse actual tool logs to detect stages
- ✅ Capture real resource consumption per stage
- ✅ Extract real design features from tool output
- ✅ Train model on actual execution data

### Log Processing Requirements (CRITICAL)

**MANDATORY**: Log processing must be lightweight, fast, and privacy-preserving

#### Performance Requirements
- **Latency**: Stage detection within <100ms of log write
- **CPU Overhead**: <1% per monitored job
- **Memory Footprint**: <10MB per monitored job
- **Throughput**: Process >10,000 log lines/second
- **Scalability**: Support 100+ concurrent jobs per node

#### Data Privacy Requirements
- **Local Processing**: All log parsing MUST happen on compute node
- **No External Transmission**: Logs MUST NOT be sent to external servers
- **On-Node Storage**: Parsed metrics stored locally before batch upload
- **Sensitive Data**: Design details stay on secure compute nodes
- **Compliance**: Meet data residency requirements for proprietary designs

#### Lightweight Requirements
- **Minimal Dependencies**: Avoid heavy runtimes (no JVM, minimal Ruby)
- **Small Binary**: <5MB executable size
- **Low Memory**: <10MB resident memory per job
- **Fast Startup**: <100ms initialization time
- **No Bloat**: Only essential features, no unnecessary plugins

#### Technology Constraints
- ✅ **ALLOWED**: Fluent Bit, inotify+C, Vector, named pipes
- ⚠️ **DISCOURAGED**: Fluentd (too heavy), Logstash (JVM overhead)
- ❌ **PROHIBITED**: Graylog (centralized), Splunk (proprietary), cloud-based solutions

#### Rationale
- **HPC/EDA workloads are sensitive**: Proprietary chip designs, confidential research
- **Compute nodes are shared**: Can't waste resources on monitoring
- **Real-time is critical**: Need immediate stage detection for resource tracking
- **Scale matters**: Hundreds of jobs running simultaneously

### Stage Detection from Real Tools

**OpenROAD Stage Markers** (from actual logs):
```
[INFO] Reading LEF file: ...                    → read_design stage
[INFO] initialize_floorplan                      → floorplan stage
[INFO] Starting global placement                 → placement stage (start)
[INFO] Global placement complete                 → placement stage (end)
[INFO] Starting clock tree synthesis             → cts stage
[INFO] Starting global routing                   → routing stage (start)
[INFO] Detailed routing complete                 → routing stage (end)
[INFO] Writing DEF: ...                          → finishing stage
```

**Resource Monitoring Requirements:**
- Monitor actual OpenROAD process (PID tracking)
- Capture real CPU/memory/IO usage via psutil or /proc
- Associate metrics with stages detected from logs
- Store actual timestamps, not simulated durations

### Data Validation

Before training model, verify:
- [ ] OpenROAD binary was actually executed
- [ ] Log files contain real OpenROAD output
- [ ] Stage detection found actual stage markers
- [ ] Resource metrics show realistic patterns
- [ ] Design features match actual design characteristics

## 1. Parallel Cluster Setup
- Configure AWS Parallel Cluster with SLURM scheduler
- Support multiple compute node types for testing
- Enable job accounting and resource tracking
- Configure SLURM with appropriate partitions

## 2. Open Source Workload Selection

### HPC Workloads
- **GROMACS** (molecular dynamics) - CPU and memory intensive
- **LAMMPS** (molecular dynamics) - MPI scaling tests
- **OpenFOAM** (CFD) - I/O and compute intensive

### EDA Workloads
- **OpenROAD** (RTL-to-GDSII flow) - Complete digital design flow
  - Stages: synthesis, floorplan, placement, CTS, routing, DRC/LVS
  - Design features: cell count, net count, die size, layer count
- **Yosys** (logic synthesis) - RTL synthesis and optimization
  - Stages: parsing, elaboration, optimization, mapping, output
  - Design features: module count, gate count, hierarchy depth
- **Magic** (layout tool) - DRC, extraction, GDS operations
  - Stages: GDS read, DRC check, extraction, GDS write
  - Design features: polygon count, layer complexity, design area
- **OpenLane** (complete flow) - Automated RTL-to-GDSII
  - Stages: synthesis, floorplan, placement, routing, signoff
  - Design features: design size, clock frequency, utilization target

## 3. SPANK Plugin Development

**Purpose**: Custom SPANK plugin is REQUIRED to extract fine-grained stage-level metrics that standard SLURM accounting cannot provide.

### Why Custom SPANK is Necessary
- Standard SLURM accounting only captures job-level aggregates
- Need per-stage resource tracking within a single job
- Must correlate tool-specific stages with resource consumption
- Required to identify bottlenecks (compute vs I/O vs memory vs dependencies)

### Stage Detection Strategy
Plugin must identify job stages by:
1. **Process name monitoring** - Detect when different EDA/HPC tools start
2. **Log file parsing** - Parse tool output for stage markers
3. **User annotations** - Allow job scripts to mark stages explicitly
4. **System call patterns** - Infer stages from I/O/compute patterns

### Metrics Captured Per Stage
For each detected stage, capture:
- **Compute**: CPU utilization, core count, CPU time
- **Memory**: RSS, virtual memory, peak usage, page faults
- **I/O**: Disk read/write bytes, IOPS, file access patterns
- **Network**: MPI communication volume, latency (for HPC)
- **Dependencies**: Wait time for external data, library load time
- **Timestamps**: Stage start, end, duration

### Data Association Model
Plugin creates mapping:
```
Design Features + Tool Config + Stage → Resource Profile
```

Example for OpenROAD placement stage:
```json
{
  "design_features": {
    "cell_count": 500000,
    "net_count": 450000,
    "die_area_um2": 10000000,
    "utilization_target": 0.7
  },
  "tool_config": {
    "tool": "openroad",
    "stage": "placement",
    "placer": "RePlAce",
    "density": 0.7,
    "threads": 16
  },
  "resource_profile": {
    "cpu_avg_util": 85.3,
    "cpu_peak_util": 98.1,
    "memory_peak_gb": 42.5,
    "memory_avg_gb": 38.2,
    "disk_read_gb": 2.1,
    "disk_write_gb": 1.8,
    "duration_sec": 1847,
    "bottleneck": "memory"
  }
}
```

### Bottleneck Detection
Plugin identifies bottlenecks by analyzing:
- **Compute-bound**: High CPU util, low I/O wait
- **Memory-bound**: High page faults, swap activity
- **I/O-bound**: High I/O wait, low CPU util
- **Dependency-bound**: Process blocked on external resources

Plugin should:
- Hook into SLURM job lifecycle events
- Log metrics to structured format (JSON)
- Minimal performance overhead (<2%)
- Export data to metrics database in real-time or batch

## 4. Resource Tracking Database

### Schema Design
Store multi-dimensional mapping:
```
Design Features × Tool Config × Stage → Resource Requirements + Bottlenecks
```

### Core Tables

**jobs**
- job_id, workload_type (HPC/EDA), tool_name, submit_time, start_time, end_time
- slurm_config: nodes, cores, memory_gb, time_limit
- status, exit_code

**design_features** (EDA-specific)
- job_id, cell_count, net_count, die_area, layer_count, hierarchy_depth
- clock_freq_mhz, utilization_target, design_complexity_score

**tool_configs**
- job_id, tool_name, tool_version, config_json
- Example: {"placer": "RePlAce", "density": 0.7, "threads": 16}

**job_stages**
- stage_id, job_id, stage_name, stage_order, start_time, end_time, duration_sec
- parent_stage_id (for nested stages)

**stage_resources**
- stage_id, timestamp
- cpu_util_pct, cpu_cores_used, cpu_time_sec
- memory_rss_gb, memory_virtual_gb, memory_peak_gb, page_faults
- disk_read_gb, disk_write_gb, disk_iops
- network_rx_gb, network_tx_gb (for MPI workloads)
- bottleneck_type (compute/memory/io/dependency)

**external_dependencies**
- stage_id, dependency_type (library/data/license)
- wait_time_sec, access_count, data_volume_gb

### Query Patterns
Enable queries like:
- "For OpenROAD placement with 500K cells, what memory is needed?"
- "Which stages are I/O bottlenecked for designs > 1M gates?"
- "How does routing time scale with net count?"
- "What's the optimal core count for synthesis stage?"

## 5. Prediction Engine

### Input Features
```
Design Features:
- cell_count, net_count, die_area, layer_count, clock_freq, utilization

Tool Config:
- tool_name, stage_name, algorithm_choice, thread_count, optimization_level

Historical Context:
- similar_design_avg_resources, stage_typical_duration
```

### Prediction Targets (Per Stage)
```
Resource Requirements:
- cpu_cores_needed, memory_gb_needed, disk_io_gb, duration_sec

Bottleneck Prediction:
- primary_bottleneck (compute/memory/io/dependency)
- bottleneck_severity (0-1 scale)

Efficiency Forecast:
- expected_cpu_utilization, expected_memory_utilization
```

### Model Architecture
Multi-output regression model:
- Separate models per workload type (HPC vs EDA)
- Separate models per tool (OpenROAD, Yosys, GROMACS, etc.)
- Stage-specific models for fine-grained prediction
- Ensemble approach for robustness

### Feature Engineering
- Design complexity score = f(cell_count, net_count, hierarchy)
- Stage difficulty index = f(design_features, tool_config)
- Historical performance percentiles
- Workload similarity clustering

### Prediction API
```python
predict_resources(
    design_features: dict,
    tool_config: dict,
    stage_name: str
) -> {
    "cpu_cores": int,
    "memory_gb": float,
    "duration_sec": float,
    "bottleneck": str,
    "confidence": float
}
```

## 6. Dynamic Resource Allocation
Implement system to:
- Analyze incoming job submission
- Query prediction engine for optimal resources
- Modify SLURM job script automatically
- Submit with adjusted parameters
- Track actual vs predicted performance

Optimization goals:
- Maximize resource utilization (>80% target)
- Minimize queue time
- Reduce cost per job
- Maintain performance requirements

## 7. Testing Framework
End-to-end validation:
- Deploy Parallel Cluster with SLURM + SPANK
- Run baseline jobs with various configs
- Collect resource data across multiple runs
- Train prediction model
- Submit new jobs with dynamic allocation
- Compare efficiency scores (baseline vs optimized)
- Generate performance reports

# Design

## Core Mapping Strategy

The system creates a multi-dimensional mapping to predict resource requirements:

```
f(Design Features, Tool Config, Stage) → Resource Requirements + Bottlenecks
```

### Example: OpenROAD Placement Stage

**Input Dimensions:**
```
Design Features:
  - cell_count: 500,000
  - net_count: 450,000
  - die_area_um2: 10,000,000
  - utilization: 0.70
  - layer_count: 6

Tool Config:
  - tool: "openroad"
  - stage: "global_placement"
  - placer_engine: "RePlAce"
  - density: 0.70
  - num_threads: 16
  - overflow_threshold: 0.1

Stage Context:
  - stage_order: 3 (after synthesis, floorplan)
  - input_def_size_mb: 450
  - previous_stage_duration: 320s
```

**Output Predictions:**
```
Resource Requirements:
  - cpu_cores_optimal: 16
  - memory_gb_required: 42
  - disk_io_gb: 4
  - duration_sec: 1850
  - temp_storage_gb: 12

Bottleneck Analysis:
  - primary_bottleneck: "memory"
  - bottleneck_severity: 0.75
  - cpu_utilization_expected: 85%
  - memory_utilization_expected: 95%
  - io_wait_pct: 5%

Optimization Recommendations:
  - increase_memory_to_gb: 48
  - reduce_threads_to: 14 (memory bandwidth limited)
  - enable_incremental_mode: true
```

### Example: Yosys Synthesis Stage

**Input Dimensions:**
```
Design Features:
  - rtl_lines_of_code: 50,000
  - module_count: 250
  - hierarchy_depth: 8
  - estimated_gate_count: 100,000
  - clock_domains: 2

Tool Config:
  - tool: "yosys"
  - stage: "techmap"
  - optimization_level: 2
  - abc_script: "resyn2"
  - target_library: "sky130_fd_sc_hd"

Stage Context:
  - stage_order: 2 (after elaboration)
  - input_rtl_size_mb: 25
```

**Output Predictions:**
```
Resource Requirements:
  - cpu_cores_optimal: 4 (limited parallelism)
  - memory_gb_required: 8
  - duration_sec: 420
  
Bottleneck Analysis:
  - primary_bottleneck: "compute"
  - single_threaded_sections: ["abc_optimization"]
  - parallelizable_sections: ["techmap"]
```

### Mapping Database Queries

The system enables queries like:

1. **Resource prediction for new design:**
```sql
SELECT AVG(memory_peak_gb), AVG(duration_sec)
FROM stage_resources sr
JOIN design_features df ON sr.job_id = df.job_id
WHERE tool_name = 'openroad' 
  AND stage_name = 'placement'
  AND df.cell_count BETWEEN 450000 AND 550000
  AND df.utilization_target BETWEEN 0.65 AND 0.75
```

2. **Bottleneck analysis:**
```sql
SELECT stage_name, bottleneck_type, COUNT(*) as frequency
FROM stage_resources
WHERE tool_name = 'openroad'
GROUP BY stage_name, bottleneck_type
ORDER BY frequency DESC
```

3. **Scaling analysis:**
```sql
SELECT df.cell_count, AVG(sr.memory_peak_gb) as avg_memory
FROM stage_resources sr
JOIN design_features df ON sr.job_id = df.job_id
WHERE stage_name = 'routing'
GROUP BY df.cell_count
ORDER BY df.cell_count
```

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
│  └────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────┘
                          │
                          ▼
              ┌───────────────────────┐
              │  Metrics Database     │
              │  (DynamoDB/RDS)       │
              └───────────────────────┘
                          │
                          ▼
              ┌───────────────────────┐
              │  Prediction Engine    │
              │  (SageMaker/Lambda)   │
              └───────────────────────┘
                          │
                          ▼
              ┌───────────────────────┐
              │  Job Optimizer        │
              │  (Python Service)     │
              └───────────────────────┘
```

## SPANK Plugin Implementation Details

### Stage Detection Methods

**1. Process Monitoring**
```c
// Monitor process tree to detect tool transitions
// Example: detect when "openroad" process starts placement
monitor_process_tree() {
  - Track process names (openroad, yosys, magic)
  - Detect child process spawns
  - Correlate with expected stage sequence
}
```

**2. Log File Parsing**
```c
// Parse tool output for stage markers
// Example OpenROAD log markers:
"[INFO] Starting global placement"
"[INFO] Global placement complete"
"[INFO] Starting detailed placement"

// Example Yosys log markers:
"Executing TECHMAP pass"
"Executing ABC pass"
"Executing OPT pass"
```

**3. User Annotations (Explicit Markers)**
```bash
# Job script can emit stage markers
echo "SPANK_STAGE_START:synthesis" > /dev/spank_control
yosys -s synthesis.tcl
echo "SPANK_STAGE_END:synthesis" > /dev/spank_control

echo "SPANK_STAGE_START:placement" > /dev/spank_control
openroad -script placement.tcl
echo "SPANK_STAGE_END:placement" > /dev/spank_control
```

**4. Design Metadata Injection**
```bash
# Job script provides design features via environment variables
export SPANK_DESIGN_CELL_COUNT=500000
export SPANK_DESIGN_NET_COUNT=450000
export SPANK_DESIGN_DIE_AREA=10000000
export SPANK_TOOL_CONFIG='{"placer":"RePlAce","threads":16}'
```

### SPANK Plugin Hooks

```c
// Key lifecycle points to capture metrics
- slurm_spank_init()           // Plugin initialization, read config
- slurm_spank_job_prolog()     // Before job starts, capture design metadata
- slurm_spank_task_init()      // Task initialization
- slurm_spank_task_post_fork() // After task fork, start monitoring thread
- slurm_spank_task_exit()      // Task completion
- slurm_spank_job_epilog()     // After job ends, finalize metrics

// Custom monitoring thread
monitor_thread() {
  while (job_running) {
    detect_current_stage()
    collect_resource_metrics()
    identify_bottlenecks()
    log_to_json()
    sleep(sampling_interval)
  }
}
```

### Metrics Collection per Stage

```c
typedef struct {
  char stage_name[64];
  time_t start_time;
  time_t end_time;
  
  // Compute metrics
  double cpu_util_avg;
  double cpu_util_peak;
  int cpu_cores_used;
  
  // Memory metrics
  uint64_t memory_rss_bytes;
  uint64_t memory_virtual_bytes;
  uint64_t memory_peak_bytes;
  uint64_t page_faults;
  
  // I/O metrics
  uint64_t disk_read_bytes;
  uint64_t disk_write_bytes;
  uint64_t disk_iops;
  
  // Bottleneck detection
  char bottleneck_type[32]; // "compute", "memory", "io", "dependency"
  double bottleneck_severity;
  
  // Design context
  char design_features_json[1024];
  char tool_config_json[1024];
} stage_metrics_t;
```

### Output Format

```json
{
  "job_id": "12345",
  "job_name": "openroad_placement_test",
  "submit_time": "2025-11-10T10:00:00Z",
  "start_time": "2025-11-10T10:05:00Z",
  "end_time": "2025-11-10T11:35:00Z",
  "design_features": {
    "cell_count": 500000,
    "net_count": 450000,
    "die_area_um2": 10000000,
    "utilization": 0.70
  },
  "stages": [
    {
      "stage_name": "floorplan",
      "stage_order": 1,
      "start_time": "2025-11-10T10:05:00Z",
      "end_time": "2025-11-10T10:15:00Z",
      "duration_sec": 600,
      "tool_config": {"threads": 8},
      "resources": {
        "cpu_util_avg": 65.2,
        "cpu_util_peak": 89.1,
        "memory_peak_gb": 12.5,
        "disk_read_gb": 1.2,
        "disk_write_gb": 0.8
      },
      "bottleneck": {
        "type": "compute",
        "severity": 0.45
      }
    },
    {
      "stage_name": "placement",
      "stage_order": 2,
      "start_time": "2025-11-10T10:15:00Z",
      "end_time": "2025-11-10T11:05:00Z",
      "duration_sec": 3000,
      "tool_config": {"placer": "RePlAce", "threads": 16},
      "resources": {
        "cpu_util_avg": 85.3,
        "cpu_util_peak": 98.1,
        "memory_peak_gb": 42.5,
        "disk_read_gb": 2.1,
        "disk_write_gb": 1.8
      },
      "bottleneck": {
        "type": "memory",
        "severity": 0.75
      }
    }
  ]
}
```

## Data Flow

1. User submits job → Job Optimizer intercepts
2. Optimizer queries Prediction Engine with job params
3. Engine returns optimal resource allocation
4. Modified job submitted to SLURM
5. SPANK plugin monitors execution
6. Metrics stored in database
7. Prediction model retrains periodically

## Efficiency Score Calculation

```
Efficiency = (Actual_Resource_Usage / Allocated_Resources) × 100

Components:
- CPU efficiency: avg_cpu_util / allocated_cores
- Memory efficiency: peak_memory / allocated_memory
- Time efficiency: actual_runtime / requested_time
- Overall: weighted average of components
```

# Implementation Tasks

## Phase 1: Infrastructure Setup
- [ ] Create Parallel Cluster configuration file
- [ ] Define compute node types and partitions
- [ ] Configure SLURM accounting
- [ ] Set up metrics storage (DynamoDB or RDS)
- [ ] Deploy cluster and verify SLURM operation

## Phase 2: Real SPANK Plugin Development (CRITICAL)

**REQUIREMENT**: Must develop and deploy ACTUAL SPANK plugin on REAL SLURM cluster, not Python simulation

### 2.1: SPANK Plugin C Implementation with Real-Time Log Analysis

**REQUIREMENT**: Real-time stage detection with minimal latency (<1 second)

- [ ] **MUST**: Write actual SPANK plugin in C (not Python mock)
- [ ] Implement SLURM SPANK API hooks:
  ```c
  int slurm_spank_init(spank_t sp, int ac, char **av)
  int slurm_spank_job_prolog(spank_t sp, int ac, char **av)
  int slurm_spank_task_post_fork(spank_t sp, int ac, char **av)
  int slurm_spank_task_exit(spank_t sp, int ac, char **av)
  int slurm_spank_job_epilog(spank_t sp, int ac, char **av)
  ```

#### Real-Time Resource Monitoring
- [ ] Implement efficient /proc filesystem polling:
  - Read `/proc/[pid]/stat` for CPU usage (lightweight)
  - Read `/proc/[pid]/status` for memory (VmRSS, VmPeak)
  - Read `/proc/[pid]/io` for disk I/O counters
  - Monitor all child processes recursively
  - Sampling interval: 1 second (configurable)
  - Use efficient buffering to minimize overhead

#### Real-Time Log Analysis Strategy

**Option 1: inotify + tail (Recommended for Efficiency)**
- [ ] Use Linux `inotify` API to watch OpenROAD log file
- [ ] Trigger on `IN_MODIFY` events (new data written)
- [ ] Read only new lines since last position (tail behavior)
- [ ] Parse new lines immediately for stage markers
- [ ] Latency: <100ms from log write to stage detection
- [ ] Implementation:
  ```c
  int inotify_fd = inotify_init();
  int watch_fd = inotify_add_watch(inotify_fd, log_file, IN_MODIFY);
  
  while (job_running) {
    struct inotify_event event;
    read(inotify_fd, &event, sizeof(event));
    
    // Read new lines from last position
    fseek(log_fp, last_position, SEEK_SET);
    while (fgets(line, sizeof(line), log_fp)) {
      detect_stage_marker(line);  // Regex match
      last_position = ftell(log_fp);
    }
  }
  ```

**Option 2: Named Pipe (FIFO) - Zero Latency**
- [ ] Alternative: Redirect OpenROAD output to named pipe
- [ ] SPANK plugin reads from pipe in real-time
- [ ] Stage detection happens as lines are written
- [ ] Latency: <10ms (immediate)
- [ ] Implementation:
  ```bash
  mkfifo /tmp/openroad_output.fifo
  openroad script.tcl > /tmp/openroad_output.fifo &
  # SPANK plugin reads from FIFO
  ```

**Option 3: eBPF/BPF for Zero-Overhead Monitoring**
- [ ] Advanced: Use eBPF to trace write() syscalls
- [ ] Intercept OpenROAD log writes at kernel level
- [ ] Parse log lines in eBPF program
- [ ] Zero overhead, real-time detection
- [ ] Requires kernel 4.4+ and BCC/libbpf

#### Efficient Stage Detection (Regex Compilation)
- [ ] Pre-compile regex patterns at plugin init:
  ```c
  regex_t regex_placement_start;
  regcomp(&regex_placement_start, "\\[INFO\\] Starting global placement", REG_EXTENDED);
  
  regex_t regex_placement_end;
  regcomp(&regex_placement_end, "\\[INFO\\] Global placement complete", REG_EXTENDED);
  ```
- [ ] Use compiled regex for fast matching (microseconds per line)
- [ ] Maintain state machine for stage transitions:
  ```c
  enum stage_state {
    STAGE_IDLE,
    STAGE_PLACEMENT,
    STAGE_ROUTING,
    // ...
  };
  ```
- [ ] Detect stage transitions immediately when marker found
- [ ] Record timestamp at transition (nanosecond precision)

#### Performance Requirements
- [ ] Stage detection latency: <1 second from log write
- [ ] Resource sampling overhead: <2% CPU
- [ ] Memory overhead: <10MB per monitored job
- [ ] Log parsing throughput: >10,000 lines/second

- [ ] Store metrics in structured format (JSON)
- [ ] Compile plugin: `gcc -shared -fPIC -o spank_monitor.so spank_monitor.c -lpcre2`

### 2.2: Local SPANK Plugin Testing
- [ ] Install SLURM locally or in Docker container
- [ ] Configure SLURM to load plugin: `/etc/slurm/plugstack.conf`
- [ ] Test plugin with simple SLURM job: `srun --job-name=test hostname`
- [ ] Verify plugin hooks are called: check SLURM logs
- [ ] Validate metrics collection on test job
- [ ] Fix any compilation or runtime errors

### 2.3: Deploy to Parallel Cluster
- [ ] **MUST**: Deploy to REAL AWS Parallel Cluster with SLURM
- [ ] Copy compiled plugin to cluster: `/opt/slurm/lib/slurm/spank_monitor.so`
- [ ] Configure SLURM plugstack.conf on all compute nodes
- [ ] Restart SLURM daemons: `systemctl restart slurmctld slurmd`
- [ ] Verify plugin loads: `scontrol show config | grep PlugStackConfig`

### 2.4: Validate on Real Cluster
- [ ] Submit test job through REAL SLURM: `sbatch test_job.sh`
- [ ] Verify SPANK plugin executes on compute node
- [ ] Check metrics are captured: inspect output JSON files
- [ ] Validate stage detection works with real OpenROAD
- [ ] Confirm resource metrics are accurate (compare with `top`, `htop`)
- [ ] Test with multiple concurrent jobs
- [ ] Measure plugin overhead (must be < 2%)

### 2.5: Integration with OpenROAD
- [ ] Create SLURM job script that runs real OpenROAD
- [ ] SPANK plugin monitors OpenROAD process
- [ ] Parse OpenROAD logs to detect stages (using inotify for real-time)
- [ ] Associate resource metrics with detected stages
- [ ] Export per-stage metrics to database
- [ ] Validate end-to-end: SLURM → SPANK → OpenROAD → Metrics

### 2.6: Real-Time Log Analysis Technology Selection

**Requirements**: Lightweight, Fast Performance, Data Privacy (on-node processing)

#### Comprehensive Technology Comparison

| Technology | Latency | Memory | CPU | Data Privacy | Complexity | Recommendation |
|------------|---------|--------|-----|--------------|------------|----------------|
| **Fluent Bit** | <50ms | 1-2MB | 0.5-1% | ✅ Local | Low | ✅ **RECOMMENDED** |
| inotify + regex | <100ms | <1MB | <1% | ✅ Local | Low | ✅ Good |
| **LogAI** | 200-500ms | 50-200MB | 3-8% | ✅ Local | Medium | ⚠️ Overkill |
| Fluentd (Ruby) | 100-500ms | 40-100MB | 2-5% | ✅ Local | Medium | ⚠️ Heavy |
| Graylog | 500ms-2s | 500MB+ | 5-10% | ❌ Centralized | High | ❌ Too heavy |
| Logstash | 500ms-2s | 200-500MB | 3-8% | ⚠️ Depends | High | ❌ Too heavy |
| Vector | <100ms | 5-10MB | 1-2% | ✅ Local | Medium | ✅ Good alternative |
| Named Pipe | <10ms | <1MB | <0.5% | ✅ Local | Medium | ✅ Good |
| eBPF tracing | <1ms | <1MB | <0.1% | ✅ Kernel | High | ⚠️ Complex |

#### Detailed Analysis

**1. Fluent Bit (RECOMMENDED for Production)**
- **Pros**:
  - ✅ Written in C (extremely lightweight)
  - ✅ Memory footprint: 1-2MB (vs Fluentd's 40-100MB)
  - ✅ CPU overhead: 0.5-1%
  - ✅ Built-in tail input with inotify
  - ✅ Real-time parsing with regex/JSON
  - ✅ Local processing (data privacy)
  - ✅ Can output to local file/database
  - ✅ No external dependencies
  - ✅ Battle-tested in production
- **Cons**:
  - Requires separate installation
  - Configuration file needed
- **Use Case**: Perfect for HPC/EDA workloads on compute nodes

**2. Fluentd (NOT Recommended - Too Heavy)**
- **Pros**:
  - Rich plugin ecosystem
  - Mature and widely used
- **Cons**:
  - ❌ Ruby-based (40-100MB memory)
  - ❌ Higher CPU overhead (2-5%)
  - ❌ Slower than Fluent Bit
  - ❌ Overkill for single-node monitoring
- **Use Case**: Better for centralized log aggregation, not per-node

**3. Vector (Good Alternative)**
- **Pros**:
  - ✅ Rust-based (fast, safe)
  - ✅ Low memory (5-10MB)
  - ✅ Good performance
  - ✅ Modern architecture
- **Cons**:
  - Newer, less battle-tested
  - Larger binary size
- **Use Case**: Good if already using Rust ecosystem

**4. Graylog (NOT Recommended - Centralized)**
- **Cons**:
  - ❌ Centralized server (data privacy concern)
  - ❌ Heavy (500MB+ memory)
  - ❌ High latency (network overhead)
  - ❌ Requires Elasticsearch/MongoDB
  - ❌ Overkill for per-job monitoring
- **Use Case**: Enterprise log management, not real-time per-job

**5. LogAI (NOT Recommended - Overkill)**
- **What it is**: Salesforce's AI-powered log analysis framework (Python)
- **Pros**:
  - ✅ AI/ML-powered anomaly detection
  - ✅ Automatic log parsing (no regex needed)
  - ✅ Pattern learning
  - ✅ Local processing possible
  - ✅ Good for complex log analysis
- **Cons**:
  - ❌ Python-based (50-200MB memory with ML models)
  - ❌ Higher CPU overhead (3-8% with ML inference)
  - ❌ Slower latency (200-500ms due to ML processing)
  - ❌ Overkill for structured OpenROAD logs
  - ❌ Requires ML model training/loading
  - ❌ More complex setup
- **Use Case**: 
  - Good for: Unstructured logs, anomaly detection, complex patterns
  - **NOT good for**: Real-time stage detection with known patterns
  - **Our case**: OpenROAD logs are structured with clear markers - don't need AI

**Why NOT LogAI for this project?**
- OpenROAD logs have **explicit stage markers** (`[INFO] Starting global placement`)
- Simple regex is sufficient and 10x faster
- Don't need anomaly detection - just stage boundaries
- ML overhead not justified for structured logs
- Would violate <1% CPU and <10MB memory requirements

**When to use LogAI:**
- Unstructured logs without clear patterns
- Need anomaly detection across many jobs
- Complex log correlation across systems
- Post-processing analysis (not real-time)

**6. Custom inotify + Regex (Good for Embedded)**
- **Pros**:
  - ✅ Minimal dependencies
  - ✅ Full control
  - ✅ Smallest footprint
  - ✅ Data stays local
- **Cons**:
  - Need to write C code
  - Less features than Fluent Bit
- **Use Case**: When can't install external tools

**Implementation Decision (Based on Requirements):**

**PRIMARY RECOMMENDATION: Fluent Bit**
- ✅ Meets all requirements: lightweight, fast, private
- ✅ Memory: 1-2MB (vs Fluentd's 40-100MB)
- ✅ CPU: 0.5-1% overhead
- ✅ Latency: <50ms
- ✅ Local processing (data privacy)
- ✅ Production-ready and battle-tested
- ✅ Built-in tail with inotify
- ✅ Regex parsing built-in
- ✅ Can output to local file/database

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
    Path         /tmp/metrics
    Format       json
```

**ALTERNATIVE: Custom inotify + C (If Fluent Bit unavailable)**
- ✅ Zero external dependencies
- ✅ Embedded in SPANK plugin
- ✅ Full control over processing
- ✅ Smallest possible footprint (<1MB)
- ⚠️ More development effort

**Why Fluent Bit over alternatives?**
- **vs Fluentd**: 40x less memory, 5x faster
- **vs Graylog**: Local processing (privacy), 500x less memory
- **vs Logstash**: No JVM overhead, 200x less memory
- **vs LogAI**: 100x less memory, 10x faster, no ML overhead for structured logs
- **vs Custom inotify**: Production-ready, less code to maintain
- **vs Vector**: More mature, smaller footprint

**Decision Matrix:**

| Requirement | Fluent Bit | LogAI | Custom inotify |
|-------------|------------|-------|----------------|
| Lightweight (<10MB) | ✅ 1-2MB | ❌ 50-200MB | ✅ <1MB |
| Fast (<100ms) | ✅ <50ms | ❌ 200-500ms | ✅ <100ms |
| Data Privacy | ✅ Local | ✅ Local | ✅ Local |
| CPU (<1%) | ✅ 0.5-1% | ❌ 3-8% | ✅ <1% |
| Production Ready | ✅ Yes | ⚠️ New | ⚠️ Custom |
| Structured Logs | ✅ Perfect | ⚠️ Overkill | ✅ Perfect |
| **TOTAL SCORE** | **6/6** | **2/6** | **5/6** |

**Verdict**: Fluent Bit is the clear winner for our requirements

**Fallback Strategy:**
1. Try Fluent Bit (if available on cluster)
2. Fall back to custom inotify+C (embedded in SPANK)
3. Last resort: Named pipe (requires job script modification)

**Code Example:**
```c
// Initialize inotify
int inotify_fd = inotify_init1(IN_NONBLOCK);
int watch_fd = inotify_add_watch(inotify_fd, 
    "/path/to/openroad.log", 
    IN_MODIFY | IN_CLOSE_WRITE);

// Monitoring loop
while (job_running) {
    struct pollfd pfd = {inotify_fd, POLLIN, 0};
    poll(&pfd, 1, 1000);  // 1 second timeout
    
    if (pfd.revents & POLLIN) {
        // Log file modified, read new lines
        read_new_log_lines();
        detect_stage_transitions();
        update_current_stage();
    }
    
    // Sample resources every second
    sample_process_resources();
}
```

## Phase 3: Real Workload Integration (CRITICAL)

**REQUIREMENT**: Must use REAL tool execution, not simulations

### 3.1: OpenROAD Installation & Verification
- [ ] Install OpenROAD on cluster (Docker or from source)
- [ ] Verify installation: `openroad -version`
- [ ] Install PDKs: SkyWater 130nm, ASAP7 (if available)
- [ ] Test basic OpenROAD flow on simple design
- [ ] Validate OpenROAD produces expected log output

### 3.2: OpenROAD Log Parser Development
- [ ] **CRITICAL**: Create parser for actual OpenROAD logs
- [ ] Implement stage detection from log markers:
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
- [ ] Extract design features from logs:
  - Cell count: `Number of instances: (\d+)`
  - Net count: `Number of nets: (\d+)`
  - Die area: `Design area (\d+) u\^2`
  - Utilization: `Utilization: ([\d.]+)`
- [ ] Parse timing information:
  - Clock period from SDC constraints
  - Slack values from timing reports
- [ ] Validate parser on sample OpenROAD logs

### 3.3: Real OpenROAD Execution with Monitoring
- [ ] Create wrapper script to run OpenROAD with monitoring
- [ ] Monitor OpenROAD process using psutil:
  - Track main process and all children
  - Sample CPU/memory every 1 second
  - Capture disk I/O counters
- [ ] Correlate resource samples with detected stages
- [ ] Store per-stage metrics:
  ```json
  {
    "stage": "placement",
    "start_time": "2025-11-10T10:00:00",
    "end_time": "2025-11-10T10:30:00",
    "duration_sec": 1800,
    "cpu_avg": 85.3,
    "cpu_peak": 98.1,
    "memory_peak_gb": 42.5,
    "disk_read_gb": 2.1,
    "disk_write_gb": 1.8
  }
  ```

### 3.4: Test Design Preparation
- [ ] Download open-source RTL designs:
  - Ibex RISC-V core (https://github.com/lowRISC/ibex)
  - PicoRV32 (https://github.com/YosysHQ/picorv32)
  - AES core (OpenCores)
  - JPEG encoder (OpenCores)
- [ ] Prepare OpenROAD flow scripts for each design
- [ ] Create design variation matrix:
  - Frequencies: 100MHz, 200MHz, 500MHz, 1GHz
  - Utilization: 50%, 60%, 70%
  - Technology: 130nm, 45nm (if available)

### 3.5: Real Data Collection
- [ ] **MUST**: Execute actual OpenROAD (not simulation)
- [ ] Run 20-50 real jobs with design variations
- [ ] For each job:
  - Execute real OpenROAD binary
  - Monitor with psutil
  - Parse OpenROAD logs
  - Extract stage boundaries
  - Capture resource metrics per stage
  - Store design features from logs
- [ ] Validate collected data:
  - All stages detected correctly
  - Resource metrics are realistic
  - Design features match actual designs
  - No mock/simulated data

### 3.6: Data Quality Validation
- [ ] Verify OpenROAD actually ran (check log files)
- [ ] Confirm stage detection accuracy > 95%
- [ ] Check resource metrics are realistic:
  - CPU utilization 0-100%
  - Memory usage scales with design size
  - Duration matches expected OpenROAD runtime
- [ ] Validate design features:
  - Cell counts match RTL complexity
  - Die area reasonable for technology node
  - Utilization within specified range

## Phase 4: Prediction Engine (CRITICAL - Real Data Only)

**REQUIREMENT**: Model must be trained on REAL execution data and validated against ACTUAL workloads

### 4.1: Database Schema for Real Metrics
- [ ] Design schema to store REAL job execution data
- [ ] Tables must capture:
  - Actual design features extracted from OpenROAD logs
  - Real resource usage per stage from SPANK plugin
  - Actual stage durations from real executions
  - Tool configuration from actual runs
- [ ] Implement data validation:
  - Reject simulated/mock data
  - Verify stage names match OpenROAD stages
  - Check resource values are realistic
  - Ensure timestamps are sequential

### 4.2: Data Ingestion from Real Sources
- [ ] Import metrics from SPANK plugin output (JSON files)
- [ ] Parse OpenROAD logs to extract design features
- [ ] Validate data quality:
  - All required fields present
  - No placeholder/mock values
  - Resource metrics within realistic bounds
  - Stage detection accuracy verified
- [ ] Store in database with provenance tracking:
  - Source: SLURM job ID
  - Cluster: hostname/node
  - Timestamp: actual execution time
  - Tool version: real OpenROAD version

### 4.3: Feature Engineering from Real Data
- [ ] Extract features from REAL design characteristics:
  - Cell count from actual synthesis
  - Net count from real netlist
  - Die area from actual floorplan
  - Clock frequency from real constraints
  - Technology node from actual PDK
- [ ] Create derived features based on real correlations:
  - Cell density = cells / die_area
  - Net-to-cell ratio = nets / cells
  - Complexity score = freq × cells
- [ ] Normalize features using real data statistics

### 4.4: Model Training on Real Data
- [ ] **MUST**: Train ONLY on real OpenROAD execution data
- [ ] Split data: 70% train, 15% validation, 15% test
- [ ] Train Ridge regression models per stage
- [ ] Validate model learns real patterns:
  - Memory scales with cell count (real correlation)
  - Duration increases with frequency (real behavior)
  - Advanced nodes require more resources (real trend)
- [ ] Cross-validate on held-out real jobs
- [ ] Reject model if trained on any simulated data

### 4.5: Prediction API with Real Validation
- [ ] Create FastAPI service for predictions
- [ ] Input: Real design features (from actual designs)
- [ ] Output: Predicted resources per stage
- [ ] Validate predictions against NEW real runs:
  - Submit new OpenROAD job with predicted resources
  - Compare predicted vs actual resource usage
  - Calculate prediction error (MAE, RMSE)
  - Require accuracy > 85% on real workloads

### 4.6: Continuous Validation
- [ ] After each real job execution:
  - Compare prediction vs actual
  - Log prediction accuracy
  - Identify prediction failures
- [ ] Retrain model periodically with new real data
- [ ] Track model drift over time
- [ ] Alert if prediction accuracy drops below threshold

## Phase 5: Dynamic Allocation System
- [ ] Build job optimizer service
- [ ] Implement SLURM job script modification
- [ ] Create submission wrapper
- [ ] Add efficiency tracking
- [ ] Implement feedback loop

## Phase 6: End-to-End Testing

### Test Flow Overview
```
1. Deploy Cluster → 2. Baseline Jobs → 3. Train Model → 4. Optimized Jobs → 5. Compare Results
```

### Detailed Test Steps

**Step 1: Cluster Deployment & Validation**
- [ ] Deploy AWS Parallel Cluster with SLURM
- [ ] Install and configure SPANK plugin
- [ ] Verify SPANK plugin loads correctly: `scontrol show config | grep PlugStackConfig`
- [ ] Test SPANK metrics collection with simple job
- [ ] Verify metrics export to database
- [ ] Install EDA tools (OpenROAD, Yosys, OpenLane)
- [ ] Install HPC tools (GROMACS)
- [ ] Validate tool installations

**Step 2: Baseline Job Execution**
- [ ] Prepare test design suite:
  - Small: 10K cells
  - Medium: 100K cells
  - Large: 500K cells
  - XLarge: 1M+ cells
- [ ] Create baseline SLURM job scripts with conservative resource allocation
- [ ] Submit 20+ jobs per design size with varying tool configs
- [ ] Monitor SPANK plugin data collection
- [ ] Validate stage detection accuracy (manual verification)
- [ ] Collect baseline efficiency metrics

**Step 3: Model Training**
- [ ] Extract features from baseline job data
- [ ] Perform exploratory data analysis
- [ ] Train prediction models per tool/stage
- [ ] Validate model accuracy (80%+ target)
- [ ] Deploy prediction API

**Step 4: Optimized Job Execution**
- [ ] Implement job optimizer service
- [ ] Submit same test designs with dynamic allocation
- [ ] Optimizer queries prediction engine
- [ ] Modified jobs submitted to SLURM
- [ ] Collect optimized job metrics

**Step 5: Comparison & Analysis**
- [ ] Calculate efficiency improvements
- [ ] Identify which stages benefit most
- [ ] Analyze prediction accuracy
- [ ] Generate performance reports
- [ ] Document findings and recommendations

### Test Validation Checklist

**SPANK Plugin Validation**
- [ ] Plugin loads without errors
- [ ] Metrics collected for all job stages
- [ ] Stage detection accuracy > 95%
- [ ] Performance overhead < 2%
- [ ] JSON output format valid
- [ ] Data successfully exported to database

**Prediction Engine Validation (Real Data Only)**
- [ ] **CRITICAL**: Model trained ONLY on real OpenROAD execution data
- [ ] No simulated/mock data in training set
- [ ] Prediction accuracy > 85% on NEW real jobs (not seen during training)
- [ ] Predictions validated by running actual OpenROAD with predicted resources
- [ ] Prediction latency < 100ms
- [ ] API handles concurrent requests
- [ ] Model coefficients show realistic relationships:
  - Memory increases with cell count
  - Duration increases with frequency
  - Advanced nodes require more resources

**Dynamic Allocation Validation (Real Workloads)**
- [ ] Job optimizer intercepts REAL SLURM submissions
- [ ] Predictions based on model trained on real data
- [ ] Resource modifications applied to actual SLURM jobs
- [ ] **CRITICAL**: Jobs run with REAL OpenROAD (not simulation)
- [ ] Actual resource usage measured by SPANK plugin
- [ ] Compare predicted vs actual for each job
- [ ] Efficiency scores improve vs baseline (real measurements)
- [ ] No job failures due to under-allocation
- [ ] Validate predictions were accurate:
  - Predicted memory ≈ actual memory (within 20%)
  - Predicted duration ≈ actual duration (within 20%)
  - Predicted CPU ≈ actual CPU usage (within 20%)

### End-to-End Test Script

```bash
#!/bin/bash
# e2e_test.sh - Complete validation workflow

echo "=== Phase 1: Cluster Validation ==="
./scripts/validate_cluster.sh
./scripts/test_spank_plugin.sh

echo "=== Phase 2: Baseline Jobs ==="
./scripts/submit_baseline_jobs.sh --design-sizes "10k,100k,500k" --runs 20

echo "=== Phase 3: Wait for completion ==="
./scripts/wait_for_jobs.sh --timeout 7200

echo "=== Phase 4: Train Model ==="
./scripts/extract_features.sh
./scripts/train_model.sh --validate

echo "=== Phase 5: Optimized Jobs ==="
./scripts/submit_optimized_jobs.sh --design-sizes "10k,100k,500k" --runs 20

echo "=== Phase 6: Wait for completion ==="
./scripts/wait_for_jobs.sh --timeout 7200

echo "=== Phase 7: Generate Report ==="
./scripts/compare_efficiency.sh --output report.html
./scripts/analyze_predictions.sh --output predictions.html

echo "=== Test Complete ==="
```

### Success Criteria

**Must Have:**
- [ ] SPANK plugin successfully captures stage-level metrics
- [ ] All test jobs complete without errors
- [ ] Prediction accuracy > 85%
- [ ] Average efficiency improvement > 15%
- [ ] No under-allocation causing job failures

**Nice to Have:**
- [ ] Prediction accuracy > 90%
- [ ] Average efficiency improvement > 25%
- [ ] Cost reduction > 15%
- [ ] Queue time reduction > 20%

### Test Artifacts

Generated outputs:
1. `baseline_metrics.json` - All baseline job metrics
2. `optimized_metrics.json` - All optimized job metrics
3. `model_performance.json` - Prediction accuracy stats
4. `efficiency_comparison.html` - Visual comparison report
5. `bottleneck_analysis.html` - Bottleneck frequency analysis
6. `scaling_curves.png` - Resource scaling vs design size
7. `cost_analysis.csv` - Cost comparison baseline vs optimized

# Testing Strategy - Two Stage Approach

## Stage 1: Full Flow with OpenROAD (Primary Validation)

### Scope
Complete end-to-end validation focusing on OpenROAD digital flow:
- SPANK plugin development and validation
- Comprehensive EDA parameter tracking
- Historical database generation
- Gradient-based differential AI model
- Full optimization loop

### OpenROAD Test Design Suite

**Public Designs:**
- RISC-V cores: Ibex, PicoRV32, VexRiscv
- AES encryption core
- JPEG encoder
- UART controller
- SPI master

**Design Variations Strategy:**

Since we have limited unique designs, create variations by modifying:

1. **Clock Frequency** (Easy - just change SDC constraints)
   ```tcl
   # In constraints.sdc
   create_clock -period 10.0 [get_ports clk]  # 100MHz
   create_clock -period 5.0 [get_ports clk]   # 200MHz
   create_clock -period 2.0 [get_ports clk]   # 500MHz
   ```

2. **Utilization** (Easy - change floorplan config)
   ```tcl
   # In OpenROAD config
   set ::env(FP_CORE_UTIL) 50  # 50% utilization
   set ::env(FP_CORE_UTIL) 60  # 60% utilization
   set ::env(FP_CORE_UTIL) 70  # 70% utilization
   ```

3. **Aspect Ratio** (Easy - change die dimensions)
   ```tcl
   set ::env(FP_ASPECT_RATIO) 1.0  # Square
   set ::env(FP_ASPECT_RATIO) 2.0  # 2:1 rectangular
   ```

4. **Power Optimization** (Medium - enable/disable features)
   ```tcl
   # Standard flow
   set ::env(CLOCK_GATING_ENABLED) 0
   
   # Low power flow
   set ::env(CLOCK_GATING_ENABLED) 1
   set ::env(SYNTH_STRATEGY) "AREA 1"  # Use multi-Vt cells
   ```

5. **Technology Node** (Hard - requires different PDK)
   - SkyWater 130nm (open source, well supported)
   - ASAP7 (if time permits)

### Enhanced Design Features Tracking

```json
{
  "design_features": {
    "basic": {
      "cell_count": 500000,
      "net_count": 450000,
      "die_area_um2": 10000000,
      "utilization_target": 0.70,
      "aspect_ratio": 1.5
    },
    "timing": {
      "clock_freq_mhz": 500,
      "clock_domains": 2,
      "clock_uncertainty_ps": 50,
      "setup_slack_target_ps": 100,
      "hold_slack_target_ps": 50
    },
    "geometry": {
      "technology_node_nm": 45,
      "metal_layers": 8,
      "routing_layers": 6,
      "pdk": "asap7",
      "std_cell_library": "asap7sc7p5t"
    },
    "power": {
      "power_optimization": true,
      "multi_vt_cells": ["lvt", "svt", "hvt"],
      "clock_gating_enabled": true,
      "power_gating_enabled": false,
      "bias_threshold_gating": true,
      "target_power_mw": 100,
      "leakage_power_target_uw": 500
    },
    "complexity": {
      "hierarchy_depth": 8,
      "macro_count": 12,
      "memory_instances": 8,
      "io_pad_count": 256,
      "design_complexity_score": 7.5
    }
  }
}
```

### SPANK Plugin - Enhanced Monitoring

Capture EDA-specific metrics per stage:

```c
typedef struct {
  // Standard metrics
  char stage_name[64];
  time_t start_time, end_time;
  double cpu_util_avg, cpu_util_peak;
  uint64_t memory_peak_bytes;
  uint64_t disk_read_bytes, disk_write_bytes;
  
  // EDA-specific metrics
  struct {
    uint64_t cell_count_processed;
    uint64_t net_count_processed;
    double worst_slack_ps;
    double total_power_mw;
    double wirelength_um;
    uint32_t drc_violations;
    uint32_t timing_violations;
    double congestion_max;
    double density_max;
  } eda_metrics;
  
  // Tool-specific outputs
  char tool_log_summary[2048];
  char bottleneck_type[32];
  double bottleneck_severity;
} openroad_stage_metrics_t;
```

### Prediction Model/Platform Selection

**DECISION: Statistical/Regression Models (Option 4)**

Starting with regression-based approach for Stage 1:

We need to choose the prediction model and platform based on:
- Data characteristics (volume, dimensionality, relationships)
- Interpretability requirements
- Deployment constraints
- Team expertise

#### Option 1: Gradient-Based Neural Network (PyTorch/TensorFlow)

**Pros:**
- Handles non-linear relationships well
- Automatic differentiation for sensitivity analysis
- Multi-task learning (predict CPU, memory, duration simultaneously)
- Can capture complex interactions between design features
- Gradient-based feature importance

**Cons:**
- Requires more training data (200+ samples minimum)
- Less interpretable than tree-based models
- Needs careful hyperparameter tuning
- Longer training time
- Requires GPU for efficient training

**Best for:**
- Complex non-linear relationships
- When sensitivity analysis is critical
- Large datasets (500+ samples)

**Implementation:**
- Framework: PyTorch or TensorFlow
- Deployment: AWS SageMaker or containerized API
- Training: GPU instances (p3.2xlarge)

---

#### Option 2: Gradient Boosting (XGBoost/LightGBM/CatBoost)

**Pros:**
- Excellent performance with tabular data
- Built-in feature importance
- Handles missing values well
- Fast training and inference
- Less data required (100+ samples)
- More interpretable than neural networks

**Cons:**
- May not capture very complex non-linear interactions
- Separate models needed for each target (CPU, memory, duration)
- No automatic differentiation for sensitivity

**Best for:**
- Tabular data with clear features
- When interpretability matters
- Smaller datasets (100-500 samples)
- Fast iteration and deployment

**Implementation:**
- Framework: XGBoost or LightGBM
- Deployment: Simple Python API or AWS Lambda
- Training: CPU instances (c5.2xlarge)

---

#### Option 3: Ensemble Approach (Hybrid)

**Pros:**
- Combines strengths of multiple models
- More robust predictions
- Can use simple models for interpretability, complex for accuracy
- Reduces overfitting risk

**Cons:**
- More complex to maintain
- Longer inference time
- Requires more engineering effort

**Best for:**
- Production systems requiring high reliability
- When both interpretability and accuracy are critical

**Implementation:**
- Combine XGBoost + Neural Network
- Use XGBoost for initial prediction, NN for refinement
- Weighted ensemble based on confidence

---

#### Selected Approach: Statistical/Regression Models

**Why Regression for Stage 1:**
- Highly interpretable - can explain predictions to stakeholders
- Fast training and inference (<1 second)
- Works with small datasets (50+ samples)
- Easy to debug and validate
- No complex dependencies (just scikit-learn)
- Provides clear coefficient interpretation
- Good baseline for future model comparison

**Limitations (acceptable for Stage 1):**
- May not capture complex non-linear relationships
- Requires thoughtful feature engineering
- Can upgrade to more complex models in Stage 2 if needed

**Implementation Details:**
- Framework: scikit-learn
- Models to try:
  - Ridge Regression (L2 regularization) - primary choice
  - Lasso Regression (L1 regularization) - for feature selection
  - ElasticNet (L1+L2) - if feature selection + regularization needed
- Deployment: Simple Flask/FastAPI REST API
- Training: Any CPU instance (c5.xlarge sufficient)
- Inference: <10ms per prediction

**Model Architecture:**
```python
from sklearn.linear_model import Ridge, Lasso, ElasticNet
from sklearn.preprocessing import StandardScaler
from sklearn.pipeline import Pipeline

# Separate model per resource type and stage
models = {
    'placement': {
        'cpu_cores': Ridge(alpha=1.0),
        'memory_gb': Ridge(alpha=1.0),
        'duration_sec': Ridge(alpha=1.0)
    },
    'routing': {
        'cpu_cores': Ridge(alpha=1.0),
        'memory_gb': Ridge(alpha=1.0),
        'duration_sec': Ridge(alpha=1.0)
    },
    # ... per stage
}

# Pipeline with standardization
pipeline = Pipeline([
    ('scaler', StandardScaler()),
    ('regressor', Ridge(alpha=1.0))
])
```

---

#### Option 5: AWS SageMaker AutoML

**Pros:**
- Automatically tries multiple algorithms
- Handles feature engineering
- Built-in deployment pipeline
- No ML expertise required
- Integrated with AWS ecosystem

**Cons:**
- Less control over model architecture
- Higher cost
- Black box approach
- May not optimize for specific use case

**Best for:**
- Quick prototyping
- When ML expertise is limited
- AWS-native deployment preferred

**Implementation:**
- Platform: AWS SageMaker Autopilot
- Deployment: Automatic endpoint creation
- Training: Managed by SageMaker

---

### Implementation Plan for Regression Model

**TODAY: Local Model Development**

- [ ] Extract features from local test runs (5-10 samples minimum)
- [ ] Create simple train/test split
- [ ] Implement Ridge regression model
- [ ] Train on local data
- [ ] Validate prediction logic works
- [ ] Create prediction API structure (FastAPI)
- [ ] Test end-to-end: design features → prediction → resource allocation

**TOMORROW: Production Model Training**

- [ ] Collect 20-50 jobs from Parallel Cluster
- [ ] Retrain model with production data
- [ ] Validate accuracy on cluster data
- [ ] Deploy prediction API to cluster or EC2
- [ ] Integrate with SLURM job submission
- [ ] Test dynamic resource allocation
- [ ] Compare baseline vs optimized jobs

**Model Interpretability Analysis:**

After training, analyze coefficients to understand:
```python
def analyze_model_coefficients(model, feature_names):
    """
    Interpret which design features most impact resources
    """
    coefficients = model.named_steps['regressor'].coef_
    
    # Sort by absolute value
    importance = sorted(
        zip(feature_names, coefficients),
        key=lambda x: abs(x[1]),
        reverse=True
    )
    
    print("Top 10 features impacting resource requirements:")
    for feature, coef in importance[:10]:
        print(f"{feature:30s}: {coef:+.4f}")
    
    # Example output:
    # log_cell_count              : +0.8234  (more cells = more memory)
    # clock_freq_ghz              : +0.4521  (higher freq = longer runtime)
    # utilization                 : +0.3891  (higher util = more memory)
    # cell_density                : -0.2134  (higher density = less routing)
```

**Upgrade Path to Advanced Models (Stage 2):**

If regression accuracy < 85%, consider:
1. Add polynomial features (degree 2) for non-linear relationships
2. Try XGBoost for automatic feature interaction
3. Implement ensemble of regression + XGBoost
4. Only move to neural networks if clear non-linear patterns exist

### Feature Engineering (Common to All Options)

Regardless of model choice, extract these features:

```python
def extract_features(design_config):
    """
    Extract normalized features for model input
    """
    features = {
        # Design size features (log-transformed for scale)
        'log_cell_count': np.log1p(design_config['cell_count']),
        'log_net_count': np.log1p(design_config['net_count']),
        'log_die_area': np.log1p(design_config['die_area_um2']),
        'utilization': design_config['utilization_target'],
        'aspect_ratio': design_config['aspect_ratio'],
        
        # Timing features (normalized)
        'clock_freq_ghz': design_config['clock_freq_mhz'] / 1000.0,
        'clock_domains': design_config['clock_domains'],
        'setup_slack_ns': design_config['setup_slack_target_ps'] / 1000.0,
        
        # Technology features (normalized to 130nm baseline)
        'tech_node_normalized': design_config['technology_node_nm'] / 130.0,
        'metal_layers': design_config['metal_layers'],
        
        # Power features (binary/categorical)
        'clock_gating': int(design_config['clock_gating_enabled']),
        'power_gating': int(design_config['power_gating_enabled']),
        'bias_gating': int(design_config['bias_threshold_gating']),
        'vt_cell_types': len(design_config['multi_vt_cells']),
        
        # Complexity features
        'hierarchy_depth': design_config['hierarchy_depth'],
        'macro_count': design_config['macro_count'],
        'memory_instances': design_config['memory_instances'],
        
        # Derived features (interaction terms)
        'cell_density': design_config['cell_count'] / design_config['die_area_um2'],
        'net_to_cell_ratio': design_config['net_count'] / design_config['cell_count'],
        'complexity_score': design_config['clock_freq_mhz'] * design_config['cell_count'] / 1e6
    }
    return features
```

### Evaluation Metrics (Common to All Options)

```python
def evaluate_model(predictions, actuals):
    """
    Evaluate prediction accuracy
    """
    metrics = {
        # Regression metrics
        'mae': mean_absolute_error(actuals, predictions),
        'rmse': np.sqrt(mean_squared_error(actuals, predictions)),
        'r2': r2_score(actuals, predictions),
        'mape': mean_absolute_percentage_error(actuals, predictions),
        
        # Custom metrics
        'within_10pct': np.mean(np.abs(predictions - actuals) / actuals < 0.10),
        'within_20pct': np.mean(np.abs(predictions - actuals) / actuals < 0.20),
        
        # Per-stage breakdown
        'per_stage_accuracy': compute_per_stage_metrics(predictions, actuals)
    }
    return metrics
```

### Stage 1 Test Execution Plan

**TODAY: Local End-to-End Flow**
- [ ] Set up local development environment
- [ ] Install OpenROAD flow locally
- [ ] Install PDK (SkyWater 130nm)
- [ ] Develop SPANK plugin (or mock for local testing)
- [ ] Prepare 2-3 small test designs
- [ ] Run local OpenROAD flow with monitoring
- [ ] Capture metrics manually or via script
- [ ] Validate data collection format
- [ ] Build initial database schema
- [ ] Test feature extraction
- [ ] Implement basic regression model
- [ ] Validate prediction pipeline locally

**TOMORROW: Parallel Cluster Deployment & Live Testing**
- [ ] Deploy AWS Parallel Cluster with SLURM
- [ ] Install OpenROAD flow on cluster
- [ ] Deploy SPANK plugin to cluster
- [ ] Configure SLURM to load plugin
- [ ] Set up PostgreSQL/RDS for metrics
- [ ] Submit 10-20 test jobs with variations
- [ ] Monitor SPANK plugin in production
- [ ] Validate metrics collection
- [ ] Verify stage detection accuracy
- [ ] Collect live data into database
- [ ] Run prediction model on live data
- [ ] Generate initial efficiency report

### Data Collection Feasibility Analysis

**Challenge:** Need diverse dataset but limited by:
- Number of available open-source designs
- Time to run each design through full flow
- Compute resources available

**Strategy: Design Variations from Limited Base Designs**

Instead of requiring 50+ unique designs, we can create variations:

**Base Designs (5-10 unique designs):**
- Ibex RISC-V core (~5K cells)
- PicoRV32 (~10K cells)
- AES core (~20K cells)
- JPEG encoder (~50K cells)
- VexRiscv (~100K cells)

**Variation Parameters (multiply dataset):**
Each base design can be varied across:

1. **Clock Frequency** (5 variations)
   - 50MHz, 100MHz, 200MHz, 500MHz, 1GHz
   - Changes timing constraints, affects placement/routing

2. **Utilization Target** (4 variations)
   - 40%, 50%, 60%, 70%
   - Affects floorplan, placement density, routing congestion

3. **Technology Node** (2-3 variations)
   - SkyWater 130nm
   - ASAP7 45nm (if available)
   - Changes cell library, affects all stages

4. **Power Optimization** (2 variations)
   - Standard flow (no power optimization)
   - Low power (clock gating + multi-Vt)

5. **Aspect Ratio** (2-3 variations)
   - 1:1 (square)
   - 2:1 (rectangular)
   - 4:1 (narrow)

**Data Generation Math:**

With 5 base designs:
- 5 designs × 5 frequencies × 4 utilizations × 2 tech nodes × 2 power modes = 400 possible combinations

**Realistic Target for Stage 1:**
- Select 3-5 base designs
- Choose subset of variations (not full factorial)
- Target: 100-150 jobs total

Example matrix:
```
Design    | Freq Variations | Util Variations | Tech | Power | Total Jobs
----------|-----------------|-----------------|------|-------|------------
Ibex      | 3 (100,200,500) | 3 (50,60,70)   | 1    | 2     | 18
PicoRV32  | 3               | 3               | 1    | 2     | 18
AES       | 3               | 3               | 1    | 2     | 18
JPEG      | 3               | 2 (60,70)      | 1    | 2     | 12
VexRiscv  | 2 (100,200)     | 2 (60,70)      | 1    | 2     | 8
----------|-----------------|-----------------|------|-------|------------
TOTAL                                                         | 74 jobs
```

**Time Estimation:**

Per job runtime (OpenROAD full flow):
- Small design (5K cells): ~10-20 minutes
- Medium design (50K cells): ~1-2 hours
- Large design (100K cells): ~2-4 hours

With parallel execution (10 compute nodes):
- 74 jobs × 1 hour average / 10 nodes = ~7.4 hours
- Add buffer for failures/reruns: ~12-16 hours total

**Minimum Viable Dataset:**

For regression model to work:
- **Minimum**: 50 jobs (barely sufficient)
- **Recommended**: 100 jobs (good for Stage 1)
- **Ideal**: 150+ jobs (strong predictions)

**Practical Approach:**

Phase 2A (Days 1-2): Quick validation
- [ ] 3 base designs × 3 variations = 9 jobs
- [ ] Validate SPANK plugin works end-to-end
- [ ] Verify data quality

Phase 2B (Days 3-5): Full collection
- [ ] Run remaining 65-90 jobs
- [ ] Parallel execution on cluster
- [ ] Monitor for failures, resubmit as needed

Phase 2C (Days 6-7): Data validation
- [ ] Check for outliers
- [ ] Verify stage detection accuracy
- [ ] Ensure sufficient variation in features

**Week 3: Model Development**
- [ ] Implement gradient-based differential model
- [ ] Train on historical data (80/20 train/test split)
- [ ] Validate prediction accuracy per stage
- [ ] Perform sensitivity analysis
- [ ] Deploy prediction API
- [ ] Test API performance

**TOMORROW (Continued): Dynamic Optimization Testing**
- [ ] Implement job optimizer service
- [ ] Submit 10-20 optimized jobs
- [ ] Compare efficiency: baseline vs optimized
- [ ] Analyze prediction accuracy
- [ ] Generate initial report

### Stage 1 Success Metrics
- [ ] SPANK plugin captures all OpenROAD stages (synthesis → signoff)
- [ ] Historical database contains 200+ job records
- [ ] Model prediction accuracy > 85% for memory, CPU, duration
- [ ] Efficiency improvement > 20% vs baseline
- [ ] Stage detection accuracy > 95%
- [ ] Plugin overhead < 2%

### Stage 1 Deliverables
1. SPANK plugin source code (C)
2. OpenROAD test design suite
3. Historical metrics database (PostgreSQL dump)
4. Gradient-based prediction model (PyTorch)
5. Job optimizer service (Python)
6. End-to-end test scripts
7. Performance analysis report
8. Sensitivity analysis showing which design features most impact resources

## Stage 2: Extended Validation (Future)

### Scope
Expand to additional workloads after Stage 1 success:
- HPC workloads (GROMACS, LAMMPS)
- Additional EDA tools (Yosys standalone, Magic)
- Multi-tool flow optimization
- Cross-workload model generalization
- Production deployment

### Stage 2 Success Metrics
- Model generalizes across workload types
- Unified prediction API for all tools
- Production-ready deployment
- Cost reduction > 15% in production

# Deliverables

1. AWS Parallel Cluster configuration
2. SPANK plugin source code and build instructions
3. Workload test cases and job scripts
4. Metrics database schema and ingestion code
5. Prediction engine implementation
6. Job optimizer service
7. End-to-end test suite
8. Performance analysis report
9. Documentation and deployment guide

# Open Questions

1. Which AWS region and instance types for compute nodes?
2. Preferred database: DynamoDB (NoSQL) or RDS (PostgreSQL)?
   - Recommend PostgreSQL for complex queries on design features
3. ML framework preference: scikit-learn, XGBoost, or TensorFlow?
4. Should we support GPU workloads in initial version?
5. Real-time vs batch prediction for job optimization?
6. Integration with AWS Cost Explorer for cost tracking?
7. For EDA workloads:
   - Which PDK to use for test designs? (SkyWater 130nm, ASAP7?)
   - Should we include analog/mixed-signal flows or digital only?
   - Need access to commercial EDA tools or open-source only?
8. Stage detection approach:
   - Instrument tool source code vs external monitoring?
   - Use tool-specific log parsers vs generic pattern matching?

# Notes

- Start with single workload (GROMACS) then expand
- SPANK plugin must be compiled for cluster OS (Amazon Linux 2)
- Consider using AWS ParallelCluster API for automation
- May need custom AMI with pre-installed workloads
- SLURM job arrays useful for batch testing
- Consider using AWS Batch as alternative scheduler for comparison
