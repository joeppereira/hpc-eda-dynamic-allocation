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

# Requirements

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

## Phase 2: SPANK Plugin Development
- [ ] Create SPANK plugin C code structure
- [ ] Implement resource monitoring functions
- [ ] Add job lifecycle hooks
- [ ] Implement metrics logging (JSON format)
- [ ] Build and test plugin locally
- [ ] Deploy plugin to Parallel Cluster
- [ ] Validate metrics collection

## Phase 3: Workload Integration

### HPC Workloads
- [ ] Install GROMACS on cluster
- [ ] Create test cases with varying parameters
- [ ] Develop job submission scripts

### EDA Workloads
- [ ] Install OpenROAD flow on cluster
- [ ] Install Yosys synthesis tool
- [ ] Set up OpenLane environment
- [ ] Prepare test designs (varying sizes: 10K, 100K, 500K, 1M+ cells)
- [ ] Create design feature extraction scripts
- [ ] Instrument EDA tools to emit stage markers
- [ ] Develop job submission scripts with design metadata

### Baseline Experiments
- [ ] Run each workload with multiple design sizes
- [ ] Vary tool configurations (threads, algorithms, optimization levels)
- [ ] Collect and validate metrics data
- [ ] Verify stage detection accuracy

## Phase 4: Prediction Engine
- [ ] Design database schema for job metrics
- [ ] Implement data ingestion pipeline
- [ ] Build feature engineering pipeline
- [ ] Train ML model (Random Forest/XGBoost)
- [ ] Create prediction API
- [ ] Validate predictions against test set

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

**Prediction Engine Validation**
- [ ] Model training completes successfully
- [ ] Prediction accuracy > 85% for resource requirements
- [ ] Prediction latency < 100ms
- [ ] API handles concurrent requests
- [ ] Confidence scores provided

**Dynamic Allocation Validation**
- [ ] Job optimizer intercepts submissions
- [ ] Resource modifications applied correctly
- [ ] Jobs complete successfully
- [ ] Efficiency scores improve vs baseline
- [ ] No job failures due to under-allocation

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

**Design Variations:**
Create test matrix with varying parameters:
- Size: 5K, 10K, 50K, 100K, 500K cells
- Frequency: 50MHz, 100MHz, 200MHz, 500MHz, 1GHz
- Geometry/Node: 130nm (SkyWater), 45nm (ASAP7), 7nm (ASAP7)
- Utilization: 40%, 50%, 60%, 70%, 80%
- Aspect ratio: 1:1, 2:1, 4:1

**Power/Optimization Features:**
- Low power modes: multi-Vt cells, power gating, clock gating
- Bias threshold: body biasing configurations
- Optimization goals: area, power, timing, balanced

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

**Week 3: Model Development**

Day 1-2: Data Preparation
- [ ] Extract features from 200+ baseline jobs
- [ ] Create train/validation/test split (70/15/15)
- [ ] Perform exploratory data analysis
- [ ] Check for correlations and outliers
- [ ] Normalize/standardize features

Day 3-4: Model Training
- [ ] Train separate Ridge models per stage and resource type
- [ ] Perform cross-validation (5-fold)
- [ ] Tune regularization parameter (alpha)
- [ ] Evaluate on validation set
- [ ] Analyze residuals and feature coefficients

Day 5: Model Validation
- [ ] Test on held-out test set
- [ ] Calculate accuracy metrics (MAE, RMSE, R², MAPE)
- [ ] Generate prediction vs actual plots
- [ ] Identify which stages/resources predict well
- [ ] Document model coefficients for interpretability

Day 6-7: API Development & Deployment
- [ ] Build FastAPI prediction service
- [ ] Add input validation
- [ ] Implement model versioning
- [ ] Deploy to EC2 or Lambda
- [ ] Load testing and performance validation

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

**Week 1: Infrastructure Setup**
- [ ] Deploy AWS Parallel Cluster (c5.4xlarge compute nodes)
- [ ] Install OpenROAD flow (latest stable)
- [ ] Install PDKs: SkyWater 130nm, ASAP7 45nm/7nm
- [ ] Develop and deploy SPANK plugin
- [ ] Set up PostgreSQL database for metrics
- [ ] Validate SPANK plugin with simple test job

**Week 2: Baseline Data Collection**
- [ ] Prepare test designs (see feasibility analysis below)
- [ ] Create design feature extraction scripts
- [ ] Submit baseline jobs covering test matrix
- [ ] Monitor and validate SPANK data collection
- [ ] Verify stage detection accuracy
- [ ] Build historical database

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

**Week 4: Dynamic Optimization**
- [ ] Implement job optimizer service
- [ ] Submit 100+ optimized jobs
- [ ] Compare efficiency: baseline vs optimized
- [ ] Analyze prediction accuracy
- [ ] Generate comprehensive report

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
