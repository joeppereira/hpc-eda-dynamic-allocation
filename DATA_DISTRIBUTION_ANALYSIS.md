# Data Distribution Analysis

## OpenROAD Stages Tracked

### Complete Stage Breakdown

| Stage | Sub-Stages | Typical Duration | Resource Profile |
|-------|-----------|------------------|------------------|
| **1. Synthesis** | Yosys canonicalize, Yosys synth | 1-5 min | CPU-intensive |
| **2. Floorplan** | Initialize, I/O placement, PDN | 30 sec - 2 min | Memory-moderate |
| **3. Placement** | Global placement, Detailed placement | 2-10 min | Memory-intensive |
| **4. CTS** | Clock tree synthesis | 30 sec - 3 min | CPU-intensive |
| **5. Routing** | Global routing, Detailed routing | 5-20 min | Memory + I/O intensive |
| **6. Finishing** | Metal fill, DRC, Final checks | 1-3 min | I/O-intensive |

**Total Stages Tracked: 6 main stages + sub-stages = ~15-20 trackable points**

---

## Design Configuration Variations

### Design Size Parameters

| Parameter | Small | Medium | Large | X-Large |
|-----------|-------|--------|-------|---------|
| **Cell Count** | 5K-10K | 50K-100K | 500K-1M | 1M-10M |
| **Net Count** | 4.5K-9K | 45K-90K | 450K-900K | 900K-9M |
| **Die Area (µm²)** | 100K-1M | 5M-20M | 50M-200M | 200M-1B |
| **Typical Design** | UART, GCD | AES, JPEG | RISC-V core | Full SoC |

### Timing Parameters

| Parameter | Values | Impact |
|-----------|--------|--------|
| **Clock Frequency** | 50MHz, 100MHz, 200MHz, 500MHz, 1GHz | Higher freq = longer placement/routing |
| **Clock Domains** | 1, 2, 4, 8 | More domains = more CTS complexity |
| **Setup Slack Target** | 50ps, 100ps, 200ps | Tighter slack = more iterations |

### Technology Parameters

| Parameter | Values | Impact |
|-----------|--------|--------|
| **Technology Node** | 130nm, 45nm, 7nm | Smaller = more routing layers, tighter rules |
| **Metal Layers** | 4, 6, 8, 10 | More layers = more routing options |
| **PDK** | SkyWater 130nm, ASAP7 | Different cell libraries, rules |

### Utilization Parameters

| Parameter | Values | Impact |
|-----------|--------|--------|
| **Utilization** | 40%, 50%, 60%, 70%, 80% | Higher = more congestion, harder routing |
| **Aspect Ratio** | 1:1, 2:1, 4:1 | Affects wirelength, routing |

### Power Optimization Parameters

| Parameter | Values | Impact |
|-----------|--------|--------|
| **Clock Gating** | Enabled/Disabled | Adds clock gating cells |
| **Power Gating** | Enabled/Disabled | Adds power switches |
| **Multi-Vt Cells** | LVT, SVT, HVT | Different threshold voltages |
| **Bias Threshold** | Enabled/Disabled | Body biasing |

---

## Tool Configuration Variations

### OpenROAD Configuration

| Parameter | Values | Impact |
|-----------|--------|--------|
| **Threads** | 1, 2, 4, 8, 16, 32 | Parallelism (diminishing returns) |
| **Placer** | RePlAce, NesterovPlace | Different algorithms |
| **Router** | FastRoute, TritonRoute | Different routing strategies |
| **Optimization Level** | 0, 1, 2, 3 | More optimization = longer runtime |

### SLURM Configuration

| Parameter | Values | Impact |
|-----------|--------|--------|
| **Nodes** | 1, 2, 4 | Distributed execution |
| **Cores per Node** | 4, 8, 16, 32 | CPU allocation |
| **Memory per Node** | 16GB, 32GB, 64GB, 128GB | Memory allocation |
| **Time Limit** | 1h, 2h, 4h, 8h | Job timeout |

---

## Data Distribution Matrix

### Test Matrix for Data Collection

To build a robust prediction model, we need diverse data:

```
Total Combinations = Designs × Frequencies × Utilizations × Technologies × Configs
                   = 5 × 5 × 4 × 2 × 3
                   = 600 possible combinations
```

### Practical Test Matrix (Manageable)

**Phase 1 (Local Testing): 20-30 jobs**
```
Designs: 3 (GCD, AES, UART)
Frequencies: 3 (100MHz, 200MHz, 500MHz)
Utilizations: 2 (60%, 70%)
Technologies: 1 (ASAP7 or SkyWater)
Configs: 1 (default)
Total: 3 × 3 × 2 × 1 × 1 = 18 jobs
```

**Phase 2 (Cluster Testing): 100-200 jobs**
```
Designs: 5 (GCD, AES, UART, JPEG, Ibex)
Frequencies: 5 (50MHz, 100MHz, 200MHz, 500MHz, 1GHz)
Utilizations: 4 (50%, 60%, 70%, 80%)
Technologies: 2 (ASAP7, SkyWater)
Configs: 2 (default, optimized)
Total: 5 × 5 × 4 × 2 × 2 = 400 jobs (sample 100-200)
```

---

## Resource Patterns by Stage

### Expected Resource Profiles

**Synthesis:**
- CPU: 60-90% utilization
- Memory: 0.5-2 GB (scales with design size)
- I/O: Low
- Duration: 1-5 minutes
- Bottleneck: CPU

**Placement:**
- CPU: 70-95% utilization
- Memory: 2-50 GB (scales with cell count²)
- I/O: Moderate
- Duration: 2-10 minutes
- Bottleneck: Memory (for large designs)

**Routing:**
- CPU: 50-80% utilization
- Memory: 5-100 GB (scales with net count)
- I/O: High (reading/writing routing database)
- Duration: 5-20 minutes
- Bottleneck: Memory + I/O

---

## Stage-Level Tracking Detail

### What We Track Per Stage

```json
{
  "stage_name": "placement",
  "sub_stage": "global_placement",
  "start_time": "2025-11-10T10:00:00Z",
  "end_time": "2025-11-10T10:15:00Z",
  "duration_sec": 900,
  
  "design_features": {
    "cell_count": 500000,
    "net_count": 450000,
    "die_area_um2": 10000000,
    "utilization": 0.70,
    "clock_freq_mhz": 500,
    "technology_node_nm": 45
  },
  
  "tool_config": {
    "placer": "RePlAce",
    "threads": 16,
    "density": 0.70
  },
  
  "resources": {
    "cpu_util_avg": 85.3,
    "cpu_util_peak": 98.1,
    "memory_peak_gb": 42.5,
    "memory_avg_gb": 38.2,
    "disk_read_gb": 2.1,
    "disk_write_gb": 1.8,
    "io_wait_pct": 5.2
  },
  
  "bottleneck": {
    "type": "memory",
    "severity": 0.75,
    "indicators": {
      "page_faults": 1250,
      "swap_usage_gb": 0.5
    }
  },
  
  "eda_metrics": {
    "worst_slack_ps": -50,
    "total_power_mw": 125.3,
    "wirelength_um": 2500000,
    "congestion_max": 0.85
  }
}
```

### Tracking Granularity

**Coarse (Stage-level):**
- 6 main stages
- Good for: Overall job prediction
- Data needed: 50-100 jobs

**Medium (Sub-stage level):**
- 15-20 sub-stages
- Good for: Stage-specific optimization
- Data needed: 100-200 jobs

**Fine (Tool-pass level):**
- 50-100 individual passes
- Good for: Detailed analysis
- Data needed: 500+ jobs

**Recommendation: Start with Medium granularity**

---

## Data Requirements for Prediction

### Minimum Data for Training

| Model Type | Minimum Samples | Recommended | Optimal |
|------------|----------------|-------------|---------|
| **Ridge Regression** | 50 | 100 | 200+ |
| **XGBoost** | 100 | 200 | 500+ |
| **Neural Network** | 200 | 500 | 1000+ |

### Data Distribution Requirements

For robust predictions, need coverage across:
- ✅ Design sizes (small, medium, large)
- ✅ Frequencies (low, medium, high)
- ✅ Utilizations (loose, medium, tight)
- ✅ Technologies (different PDKs)
- ✅ Tool configurations (threads, algorithms)

### Current Status

**Phase 1 (Local):**
- Collected: 0 real jobs (OpenROAD running)
- Target: 20-30 jobs
- Coverage: Basic (3 designs × 3 freqs × 2 utils)

**Phase 2 (Cluster):**
- Target: 100-200 jobs
- Coverage: Comprehensive

---

## Prediction Accuracy by Data Volume

### Expected Accuracy

| Data Volume | Prediction Accuracy | Confidence |
|-------------|-------------------|------------|
| **20-30 jobs** | 70-80% | Low |
| **50-100 jobs** | 80-90% | Medium |
| **100-200 jobs** | 85-95% | High |
| **200+ jobs** | 90-95%+ | Very High |

### Accuracy by Stage

Different stages have different predictability:

| Stage | Predictability | Reason |
|-------|---------------|--------|
| **Synthesis** | High (90%+) | Linear scaling with design size |
| **Floorplan** | High (85%+) | Deterministic algorithms |
| **Placement** | Medium (80-85%) | Depends on congestion |
| **CTS** | High (85%+) | Predictable clock tree |
| **Routing** | Medium (75-85%) | Congestion-dependent |
| **Finishing** | High (90%+) | Mostly I/O bound |

---

## Summary

### Stages Tracked
- **6 main stages** (synthesis → finishing)
- **15-20 sub-stages** (detailed tracking)
- **50+ tool passes** (fine-grained, optional)

### Design Variations
- Size: 5K - 10M cells
- Frequency: 50MHz - 1GHz
- Utilization: 40% - 80%
- Technology: 130nm - 7nm
- Power modes: Standard, low-power, ultra-low-power

### Tool Variations
- Threads: 1-32
- Algorithms: Multiple placers/routers
- Optimization levels: 0-3

### Data Requirements
- Minimum: 50 jobs for basic predictions
- Recommended: 100-200 jobs for production
- Optimal: 500+ jobs for high accuracy

### Current Plan
- Phase 1: 20-30 local jobs (basic coverage)
- Phase 2: 100-200 cluster jobs (comprehensive)
