# End-to-End Prediction Flow Summary

## Complete Flow: Design → Prediction → SLURM → SPANK → Adjustment

### Flow Diagram

```
┌─────────────────┐
│  New Design     │
│  Submission     │
└────────┬────────┘
         │
         ▼
┌─────────────────────────────────────────┐
│ PHASE 1: PRE-JOB PREDICTION             │
│                                         │
│ Input: Design features + Tool config   │
│ Process: Query prediction model         │
│ Output: Predicted resources per stage  │
│   - CPU cores                           │
│   - Memory GB                           │
│   - Duration sec                        │
└────────┬────────────────────────────────┘
         │
         ▼
┌─────────────────────────────────────────┐
│ PHASE 2: GENERATE SLURM JOB            │
│                                         │
│ Create SLURM script with:               │
│   #SBATCH --ntasks=<predicted_cpu>      │
│   #SBATCH --mem=<predicted_mem>G        │
│   #SBATCH --time=<predicted_time>       │
│                                         │
│ Add 20% buffer for safety              │
└────────┬────────────────────────────────┘
         │
         ▼
┌─────────────────────────────────────────┐
│ Submit to SLURM                         │
│ $ sbatch openroad_job.sh                │
└────────┬────────────────────────────────┘
         │
         ▼
┌─────────────────────────────────────────┐
│ PHASE 3: REAL-TIME MONITORING           │
│                                         │
│ SPANK Plugin monitors each stage:       │
│   - Synthesis starts                    │
│   - Monitor CPU, memory, I/O            │
│   - Synthesis completes                 │
│   - Compare actual vs predicted         │
│                                         │
│ Fluent Bit parses logs:                 │
│   - Detect stage transitions            │
│   - Extract stage boundaries            │
│   - Timestamp each stage                │
└────────┬────────────────────────────────┘
         │
         ▼
┌─────────────────────────────────────────┐
│ PHASE 4: DYNAMIC ADJUSTMENT             │
│                                         │
│ After each stage:                       │
│   IF actual > predicted by >20%:        │
│     - Calculate adjustment factor       │
│     - Update predictions for remaining  │
│     - Modify SLURM job resources        │
│     - $ scontrol update JobId=...       │
│                                         │
│   ELSE:                                 │
│     - Continue with current allocation  │
└────────┬────────────────────────────────┘
         │
         ▼
┌─────────────────────────────────────────┐
│ Repeat for each stage:                  │
│   - Placement                           │
│   - CTS                                 │
│   - Routing                             │
│   - Finishing                           │
└────────┬────────────────────────────────┘
         │
         ▼
┌─────────────────────────────────────────┐
│ PHASE 5: FINAL REPORT                   │
│                                         │
│ Generate accuracy report:               │
│   - Prediction errors per stage         │
│   - Overall accuracy metrics            │
│   - Adjustments made                    │
│   - Efficiency improvements             │
│                                         │
│ Update prediction model:                │
│   - Add new data to training set        │
│   - Retrain periodically                │
│   - Improve future predictions          │
└─────────────────────────────────────────┘
```

---

## Data Distribution

### Stages Tracked: 6 Main Stages

1. **Synthesis** (Yosys)
2. **Floorplan** (OpenROAD)
3. **Placement** (OpenROAD)
4. **CTS** (OpenROAD)
5. **Routing** (OpenROAD)
6. **Finishing** (OpenROAD)

### Design Configuration Variations

**Size Variations:**
- Small: 5K-10K cells
- Medium: 20K-50K cells
- Large: 100K-500K cells
- X-Large: 1M+ cells

**Timing Variations:**
- Frequency: 50MHz, 100MHz, 200MHz, 500MHz, 1GHz
- Clock domains: 1, 2, 4
- Slack targets: 50ps, 100ps, 200ps

**Technology Variations:**
- Node: 130nm, 45nm, 7nm
- PDK: SkyWater, ASAP7
- Metal layers: 4, 6, 8, 10

**Utilization Variations:**
- 40%, 50%, 60%, 70%, 80%

**Power Variations:**
- Standard flow
- Clock gating enabled
- Power gating enabled
- Multi-Vt cells (LVT, SVT, HVT)

### Tool Configuration Variations

**Thread Count:**
- 1, 2, 4, 8, 16, 32

**Algorithms:**
- Placer: RePlAce, NesterovPlace
- Router: FastRoute, TritonRoute

**Optimization:**
- Level: 0, 1, 2, 3

---

## Test Matrix

### Phase 1 (Local): 20-30 Jobs

```
Designs: 3 (GCD, AES, UART)
× Frequencies: 3 (100MHz, 200MHz, 500MHz)
× Utilizations: 2 (60%, 70%)
× Technologies: 1 (ASAP7)
= 18 jobs
```

### Phase 2 (Cluster): 100-200 Jobs

```
Designs: 5 (GCD, AES, UART, JPEG, Ibex)
× Frequencies: 5 (50MHz, 100MHz, 200MHz, 500MHz, 1GHz)
× Utilizations: 4 (50%, 60%, 70%, 80%)
× Technologies: 2 (ASAP7, SkyWater)
× Configs: 2 (default, optimized)
= 400 combinations (sample 100-200)
```

---

## Example: New Design Test

### Scenario: Submit AES Encryption Core

**Step 1: Design Features**
```json
{
  "cell_count": 25000,
  "net_count": 22500,
  "clock_freq_mhz": 250,
  "utilization_target": 0.65,
  "technology_node_nm": 45
}
```

**Step 2: Pre-Job Prediction**
```
Synthesis:   4 cores, 2GB,  120 sec
Placement:   8 cores, 12GB, 480 sec
Routing:     8 cores, 18GB, 720 sec
Total:       8 cores, 18GB, 22 min
```

**Step 3: SLURM Job Generated**
```bash
#SBATCH --ntasks=10      # 8 + 20% buffer
#SBATCH --mem=22G        # 18 + 20% buffer
#SBATCH --time=00:30:00  # 22min + buffer
```

**Step 4: Execution & Monitoring**
```
Synthesis starts:
  Predicted: 4 cores, 2GB, 120 sec
  Actual:    4.5 cores, 2.3GB, 125 sec
  Error:     12.5%, 15%, 4.2%
  Action:    No adjustment (error < 20%)

Placement starts:
  Predicted: 8 cores, 12GB, 480 sec
  Actual:    8.2 cores, 15GB, 510 sec
  Error:     2.5%, 25%, 6.3%
  Action:    ADJUST! Memory error > 20%
  
  Adjustment:
    Memory factor: 15/12 = 1.25x
    New routing prediction: 18GB × 1.25 = 22.5GB
    SLURM update: scontrol update JobId=123 MinMemoryNode=25G
```

**Step 5: Final Report**
```
Overall Accuracy:
  CPU:      95% accurate
  Memory:   82% accurate (improved after adjustment)
  Duration: 94% accurate

Adjustments Made: 1
  After placement: Increased memory allocation

Efficiency:
  Without adjustment: Would have failed (OOM)
  With adjustment: Completed successfully
  Resource utilization: 88% (vs 65% with static allocation)
```

---

## Implementation Status

### ✅ Completed
- Phase 1: Pre-job prediction logic
- Phase 2: SLURM job generation
- Phase 3: Monitoring framework
- Phase 4: Adjustment calculation
- Phase 5: Reporting

### ⏳ In Progress
- Real OpenROAD execution (running)
- Fluent Bit log capture (active)

### 📋 Next Steps
1. Wait for OpenROAD to complete
2. Parse real logs with Fluent Bit
3. Extract actual metrics
4. Run e2e_prediction_flow.py with real data
5. Validate complete flow

---

## Run the Test

```bash
# Once model is trained on real data:
python3 scripts/e2e_prediction_flow.py
```

This will demonstrate the complete flow from design submission to dynamic resource adjustment.
