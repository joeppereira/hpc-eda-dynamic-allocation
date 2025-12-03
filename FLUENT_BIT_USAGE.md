# Fluent Bit Usage in HPC Resource Optimization

## Where Fluent Bit is Used

Fluent Bit is used **ONLY on AWS compute nodes** for real-time OpenROAD log parsing to detect stage boundaries.

### Current Status

| Environment | Log Processing | Status |
|-------------|----------------|--------|
| **Phase 1 (Local)** | Python log parser | ✅ Working |
| **Phase 2 (AWS)** | Fluent Bit | 📋 Configured, not deployed yet |

### Why Fluent Bit?

**Purpose**: Detect when OpenROAD transitions between stages (synthesis → placement → routing)

**Requirements Met**:
- ✅ Lightweight: 1-2MB memory (vs 40-100MB for alternatives)
- ✅ Fast: <50ms latency
- ✅ Local processing: Data stays on compute node (privacy)
- ✅ Real-time: Detects stages as they happen
- ✅ Low CPU: <1% overhead

**Alternative Considered**: Custom C code in SPANK plugin (also viable)

---

## Fluent Bit Configuration

### Location in Project

```
aws/scripts/setup-head-node.sh
  └─ Creates: /shared/config/fluent-bit.conf

aws/scripts/setup-compute-node.sh
  └─ Installs Fluent Bit on compute nodes
  └─ Copies config from /shared/config/
```

### Configuration File

```yaml
# /shared/config/fluent-bit.conf

[SERVICE]
    Flush        1
    Log_Level    info
    Daemon       off

[INPUT]
    Name         tail
    Path         /shared/logs/openroad_*.log
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
    Regex        message (Starting|complete|Writing|initialize)
    
[OUTPUT]
    Name         file
    Match        openroad
    Path         /shared/metrics/stage_events
    Format       json
```

### What It Does

1. **Tails OpenROAD log files** in real-time
2. **Parses log lines** with regex
3. **Filters for stage markers**:
   - `[INFO] Starting global placement` → placement_start
   - `[INFO] Global placement complete` → placement_end
   - `[INFO] Starting clock tree` → cts_start
   - etc.
4. **Outputs to JSON** file on local node
5. **SPANK plugin reads** these events to know current stage

---

## Can We Skip Fluent Bit?

**YES!** We have two options:

### Option 1: Use Fluent Bit (Current Plan)
- ✅ Lightweight and fast
- ✅ Battle-tested
- ✅ Easy configuration
- ⚠️ Extra dependency

### Option 2: Embed in SPANK Plugin (Alternative)
- ✅ No external dependencies
- ✅ Full control
- ✅ Slightly faster
- ⚠️ More C code to write

**Recommendation**: Start with Fluent Bit (easier), can switch to embedded later if needed.

---

## Data Flow with Fluent Bit

```
OpenROAD running
    ↓
Writes to /shared/logs/openroad_job123.log
    ↓
Fluent Bit tails log file (inotify)
    ↓
Detects stage marker: "[INFO] Starting global placement"
    ↓
Writes event to /shared/metrics/stage_events/job123.json
    ↓
SPANK plugin reads event
    ↓
SPANK plugin: "Now in placement stage, start tracking placement metrics"
    ↓
SPANK plugin samples CPU/memory/IO every 1 sec
    ↓
Associates samples with "placement" stage
```

---

## Privacy & Security

**All processing happens locally on compute node:**
- ✅ Logs never leave the node
- ✅ No external transmission
- ✅ Fluent Bit writes to local filesystem
- ✅ SPANK plugin reads from local filesystem
- ✅ Only aggregated metrics sent to database (no logs)

**What gets stored in database:**
- ✅ Stage name: "placement"
- ✅ Duration: 1800 seconds
- ✅ Memory: 42.5 GB
- ✅ CPU: 85% average
- ❌ NO log contents
- ❌ NO design details from logs
- ❌ NO proprietary information

---

## Fluent Bit vs Alternatives

| Feature | Fluent Bit | Custom C | Python |
|---------|------------|----------|--------|
| Memory | 1-2MB | <1MB | 50-100MB |
| CPU | <1% | <0.5% | 2-5% |
| Latency | <50ms | <10ms | 100-500ms |
| Setup | Easy | Medium | Easy |
| Dependencies | 1 binary | None | Python runtime |
| **Recommendation** | ✅ **Use** | ✅ Good | ❌ Too heavy |

---

## When Fluent Bit Runs

**Phase 1 (Local)**: NOT USED
- Using Python log parser instead
- Simpler for local testing

**Phase 2 (AWS)**: USED
- Installed on compute nodes
- Runs as systemd service
- Starts automatically when node boots
- Monitors all OpenROAD jobs

---

## Summary

**Fluent Bit Usage:**
- 📍 **Where**: AWS compute nodes only
- 🎯 **Purpose**: Real-time stage detection from OpenROAD logs
- 🔒 **Privacy**: All processing local, no external transmission
- ⚡ **Performance**: <1% CPU, <2MB memory, <50ms latency
- 🔄 **Alternative**: Can embed in SPANK plugin if preferred

**Bottom Line**: Fluent Bit is a lightweight helper for stage detection. It's optional but recommended for ease of deployment.
