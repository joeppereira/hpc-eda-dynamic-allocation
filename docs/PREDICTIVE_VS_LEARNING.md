# Predictive vs Learning Approaches

## Quick Comparison

### Current System (Predictive)
```
User submits → Plugin calculates → Adjusts BEFORE job runs
```
- Uses **formula**: `memory = 2000 + (gates * 8 / 100) * 1.2`
- Works immediately (no training needed)
- Fixed accuracy (doesn't improve)
- May over/under-allocate for specific designs

### Proposed System (Learning)
```
User submits → Plugin queries history → Adjusts based on ACTUAL past usage
```
- Uses **historical data** + ML model
- Requires initial runs to collect data
- Accuracy **improves over time**
- Adapts to specific design characteristics

## Detailed Comparison

| Feature | Predictive | Learning |
|---------|-----------|----------|
| **First run accuracy** | Medium (formula-based) | Low (uses defaults) |
| **10th run accuracy** | Medium (same formula) | High (learned pattern) |
| **Setup complexity** | Low (just install plugin) | Medium (API + database) |
| **Maintenance** | Manual formula updates | Automatic improvement |
| **Data requirements** | None | Historical job data |
| **Confidence tracking** | No | Yes (high/medium/low) |
| **Design-specific** | No (generic formula) | Yes (learns per design) |
| **Extrapolation** | Poor (formula breaks) | Better (model detects) |

## Example: AES Cipher Design

### Predictive Approach

**Every run uses same formula:**
```
Gates: 50,000
Formula: 2000 + (50000 * 8 / 100) * 1.2 = 6,800 MB

Run 1: Predict 6.8 GB → Actual 4.2 GB (over-allocated)
Run 2: Predict 6.8 GB → Actual 4.3 GB (over-allocated)
Run 3: Predict 6.8 GB → Actual 4.1 GB (over-allocated)
...
Run 100: Predict 6.8 GB → Actual 4.2 GB (still over-allocated)
```

**Result**: Wastes ~2.6 GB per job, never improves

### Learning Approach

**Learns from actual usage:**
```
Run 1: No data → Use default 4 GB → Actual 4.2 GB → Store
Run 2: Query DB → Found 4.2 GB → Predict 5 GB → Actual 4.3 GB → Store
Run 3: Query DB → Average 4.25 GB → Predict 5.1 GB → Actual 4.1 GB → Store
...
Run 10: Model trained → Predict 4.9 GB → Actual 4.2 GB → Optimal!
```

**Result**: Converges to optimal allocation, saves resources

## When to Use Each

### Use Predictive When:
- ✅ No historical data available
- ✅ Need immediate results
- ✅ Simple, uniform workloads
- ✅ Formula is well-established
- ✅ Minimal infrastructure

### Use Learning When:
- ✅ Have or can collect historical data
- ✅ Diverse workload types
- ✅ Want continuous improvement
- ✅ Need confidence metrics
- ✅ Can run API service

## Hybrid Approach (Best of Both)

Combine both approaches:

```lua
function slurm_job_submit(job_desc, part_list, submit_uid)
    -- Try learning first
    local prediction = query_prediction_api(...)
    
    if prediction and prediction.confidence == "high" then
        -- Use learned value
        job_desc.min_mem_per_node = prediction.memory_mb
    else
        -- Fall back to formula
        local formula_mem = calculate_formula(gates)
        job_desc.min_mem_per_node = formula_mem
    end
    
    return slurm.SUCCESS
end
```

**Benefits:**
- Works immediately (formula)
- Improves over time (learning)
- Graceful degradation (fallback)
- Best of both worlds

## Real-World Scenario

### Company: EDA Design House

**Month 1 (Predictive only):**
- 1000 jobs submitted
- Formula allocates average 8 GB per job
- Actual usage: 5 GB average
- Wasted: 3 GB × 1000 = 3,000 GB-hours
- Cost: $150 wasted

**Month 2 (Switch to Learning):**
- First 100 jobs: Still learning (similar waste)
- Next 900 jobs: Model trained
- Allocates average 6 GB per job
- Actual usage: 5 GB average
- Wasted: 1 GB × 900 = 900 GB-hours
- Cost: $45 wasted
- **Savings: $105 (70% reduction)**

**Month 3+ (Fully Learned):**
- All jobs use learned allocations
- Allocates average 5.5 GB per job
- Actual usage: 5 GB average
- Wasted: 0.5 GB × 1000 = 500 GB-hours
- Cost: $25 wasted
- **Savings: $125 (83% reduction)**

## Implementation Recommendation

**Phase 1: Deploy Predictive (Week 1)**
- Install `job_submit_dynamic.lua`
- Use formula-based allocation
- Start collecting metrics

**Phase 2: Add Learning (Week 2-4)**
- Deploy prediction API
- Set up database
- Train initial model
- Run in shadow mode (log predictions, don't adjust)

**Phase 3: Hybrid Mode (Week 5+)**
- Use learning for high-confidence predictions
- Fall back to formula for new designs
- Continuous improvement

**Phase 4: Full Learning (Month 3+)**
- Sufficient historical data
- Disable formula fallback
- Pure learning-based allocation

## Code Comparison

### Predictive Plugin
```lua
-- Simple, immediate
function slurm_job_submit(job_desc, part_list, submit_uid)
    local gates = job_desc.environment["DESIGN_GATES"]
    local mem_mb = 2000 + (gates * 8 / 100) * 1.2
    job_desc.min_mem_per_node = mem_mb
    return slurm.SUCCESS
end
```

### Learning Plugin
```lua
-- Smarter, requires infrastructure
function slurm_job_submit(job_desc, part_list, submit_uid)
    local gates = job_desc.environment["DESIGN_GATES"]
    local design = job_desc.environment["DESIGN_NAME"]
    
    -- Query API
    local prediction = query_api(design, gates)
    
    if prediction and prediction.confidence ~= "low" then
        -- Use learned value
        job_desc.min_mem_per_node = prediction.memory_mb
    else
        -- Fallback to formula
        local mem_mb = 2000 + (gates * 8 / 100) * 1.2
        job_desc.min_mem_per_node = mem_mb
    end
    
    return slurm.SUCCESS
end
```

## Conclusion

**Your question was spot-on**: The current system predicts BEFORE execution, which is less accurate than learning FROM execution.

**Recommendation**: Implement the learning-based system for:
- Better accuracy over time
- Design-specific optimization
- Confidence tracking
- Continuous improvement

The system will naturally evolve from conservative defaults to optimal allocations as it learns from real workload behavior.
