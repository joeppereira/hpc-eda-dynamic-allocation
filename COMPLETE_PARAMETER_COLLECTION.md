# Complete Parameter Collection & Secure Prediction Engine

## Priority 1: Complete Parameter Collection

### Current Parameter Coverage

#### ✅ Currently Collected (Phase 1)

**Design Features:**
```python
{
    'cell_count': 50000,              # ✅ Collected
    'net_count': 45000,               # ✅ Collected
    'die_area_um2': 10000000,         # ✅ Collected
    'utilization_target': 0.7,        # ✅ Collected
    'aspect_ratio': 1.0,              # ✅ Collected
    'clock_freq_mhz': 500,            # ✅ Collected
    'clock_domains': 1,               # ✅ Collected
    'technology_node_nm': 130,        # ✅ Collected
    'metal_layers': 6,                # ✅ Collected
    'hierarchy_depth': 3,             # ✅ Collected
    'macro_count': 0,                 # ✅ Collected
}
```

**Resource Metrics (Per Stage):**
```python
{
    'cpu_util_avg': 85.3,             # ✅ Collected (psutil)
    'cpu_util_peak': 98.1,            # ✅ Collected (psutil)
    'memory_peak_gb': 42.5,           # ✅ Collected (psutil)
    'memory_avg_gb': 38.2,            # ✅ Collected (psutil)
    'disk_read_gb': 2.1,              # ✅ Collected (psutil)
    'disk_write_gb': 1.8,             # ✅ Collected (psutil)
    'duration_sec': 1800,             # ✅ Collected (time)
}
```

#### ⚠️ Missing Parameters (Need to Add)

**Design Features (EDA-Specific):**
```python
{
    # Timing parameters
    'setup_slack_target_ps': 100,     # ⚠️ NOT collected yet
    'hold_slack_target_ps': 50,       # ⚠️ NOT collected yet
    'clock_uncertainty_ps': 50,       # ⚠️ NOT collected yet
    
    # Power parameters
    'clock_gating_enabled': True,     # ⚠️ NOT collected yet
    'power_gating_enabled': False,    # ⚠️ NOT collected yet
    'multi_vt_cells': ['lvt','svt'], # ⚠️ NOT collected yet
    'target_power_mw': 100,           # ⚠️ NOT collected yet
    
    # Memory/IO parameters
    'memory_instances': 8,            # ⚠️ NOT collected yet
    'io_pad_count': 256,              # ⚠️ NOT collected yet
    
    # Design complexity
    'design_complexity_score': 7.5,   # ⚠️ NOT collected yet (derived)
}
```

**Tool Configuration:**
```python
{
    'tool': 'openroad',               # ✅ Collected
    'tool_version': '2.0',            # ⚠️ NOT collected yet
    'threads': 4,                     # ✅ Collected
    
    # Stage-specific configs
    'placer_engine': 'RePlAce',       # ⚠️ NOT collected yet
    'router_engine': 'TritonRoute',   # ⚠️ NOT collected yet
    'optimization_level': 2,          # ⚠️ NOT collected yet
}
```

**Resource Metrics (Additional):**
```python
{
    # CPU details
    'cpu_cores_used': 8,              # ⚠️ NOT collected yet
    'cpu_time_sec': 6800,             # ⚠️ NOT collected yet
    
    # Memory details
    'page_faults': 12500,             # ⚠️ NOT collected yet
    'swap_usage_gb': 0.0,             # ⚠️ NOT collected yet
    
    # I/O details
    'disk_iops': 1500,                # ⚠️ NOT collected yet
    
    # Network (for MPI jobs)
    'network_rx_gb': 0.0,             # ⚠️ NOT collected yet (not needed for OpenROAD)
    'network_tx_gb': 0.0,             # ⚠️ NOT collected yet (not needed for OpenROAD)
    
    # Bottleneck analysis
    'bottleneck_type': 'memory',      # ✅ Collected (basic)
    'bottleneck_severity': 0.75,      # ⚠️ NOT collected yet
}
```

**Stage-Specific Metrics:**
```python
{
    # Placement stage
    'wirelength_um': 1500000,         # ⚠️ NOT collected yet
    'congestion_max': 0.85,           # ⚠️ NOT collected yet
    'density_max': 0.92,              # ⚠️ NOT collected yet
    
    # Routing stage
    'drc_violations': 0,              # ⚠️ NOT collected yet
    'wire_length_total_um': 2000000,  # ⚠️ NOT collected yet
    
    # Timing
    'worst_slack_ps': -50,            # ⚠️ NOT collected yet
    'tns_ps': -500,                   # ⚠️ NOT collected yet
}
```

---

## Implementation Plan: Complete Parameter Collection

### Phase 2A: Enhanced Log Parsing (Week 1)

**Goal**: Extract ALL design parameters from OpenROAD logs

**Implementation**:

```python
# Enhanced log parser
class OpenROADLogParser:
    def parse_design_features(self, log_file):
        """Extract complete design features from logs"""
        features = {}
        
        with open(log_file) as f:
            for line in f:
                # Cell count
                if 'Number of instances:' in line:
                    features['cell_count'] = int(re.search(r'(\d+)', line).group(1))
                
                # Net count
                if 'Number of nets:' in line:
                    features['net_count'] = int(re.search(r'(\d+)', line).group(1))
                
                # Die area
                if 'Design area' in line:
                    features['die_area_um2'] = float(re.search(r'([\d.]+)', line).group(1))
                
                # Utilization
                if 'Utilization:' in line:
                    features['utilization_target'] = float(re.search(r'([\d.]+)', line).group(1))
                
                # Clock frequency (from SDC)
                if 'create_clock' in line and '-period' in line:
                    period_ns = float(re.search(r'-period\s+([\d.]+)', line).group(1))
                    features['clock_freq_mhz'] = 1000.0 / period_ns
                
                # NEW: Timing parameters
                if 'set_clock_uncertainty' in line:
                    features['clock_uncertainty_ps'] = float(re.search(r'([\d.]+)', line).group(1)) * 1000
                
                # NEW: Power parameters
                if 'clock_gating' in line.lower():
                    features['clock_gating_enabled'] = 'enable' in line.lower()
                
                # NEW: Placement metrics
                if 'Total wirelength:' in line:
                    features['wirelength_um'] = float(re.search(r'([\d.]+)', line).group(1))
                
                if 'Max congestion:' in line:
                    features['congestion_max'] = float(re.search(r'([\d.]+)', line).group(1))
                
                # NEW: Routing metrics
                if 'DRC violations:' in line:
                    features['drc_violations'] = int(re.search(r'(\d+)', line).group(1))
                
                # NEW: Timing results
                if 'Worst slack:' in line:
                    features['worst_slack_ps'] = float(re.search(r'([-\d.]+)', line).group(1)) * 1000
        
        return features
```

**Files to Update**:
- `monitoring/resource_monitor.py` - Add enhanced log parsing
- `database/schema.py` - Add new columns to tables
- `prediction/model.py` - Add new features to feature vector

### Phase 2B: Enhanced SPANK Plugin (Week 2)

**Goal**: Collect ALL resource metrics

**Implementation**:

```c
// Enhanced SPANK plugin metrics
typedef struct {
    // Existing metrics
    long cpu_utime, cpu_stime;
    long memory_rss, memory_vsize;
    long io_read_bytes, io_write_bytes;
    
    // NEW: Additional CPU metrics
    int cpu_cores_used;
    long cpu_time_total_sec;
    
    // NEW: Additional memory metrics
    long page_faults_major;
    long page_faults_minor;
    long swap_usage_bytes;
    
    // NEW: I/O metrics
    long disk_iops_read;
    long disk_iops_write;
    
    // NEW: Derived metrics
    float cpu_efficiency;      // actual_usage / allocated
    float memory_efficiency;   // peak_usage / allocated
    char bottleneck_type[32];  // 'compute', 'memory', 'io'
    float bottleneck_severity; // 0.0 - 1.0
} enhanced_resource_sample_t;

// Read from /proc/[pid]/status for detailed memory
static int read_proc_status(pid_t pid, long *swap, long *page_faults) {
    char path[256];
    FILE *fp;
    char line[256];
    
    snprintf(path, sizeof(path), "/proc/%d/status", pid);
    fp = fopen(path, "r");
    if (!fp) return -1;
    
    while (fgets(line, sizeof(line), fp)) {
        if (strncmp(line, "VmSwap:", 7) == 0) {
            sscanf(line + 7, "%ld", swap);
        }
        // Add more parsing...
    }
    
    fclose(fp);
    return 0;
}
```

### Phase 2C: Tool Configuration Capture (Week 2)

**Goal**: Capture exact tool settings used

**Implementation**:

```python
# Capture tool configuration from job script
def extract_tool_config(job_script):
    """Extract tool configuration from SLURM job script"""
    config = {}
    
    with open(job_script) as f:
        content = f.read()
        
        # OpenROAD version
        if 'openroad' in content:
            # Extract from docker image tag or binary path
            match = re.search(r'openroad[:/](\d+\.\d+)', content)
            if match:
                config['tool_version'] = match.group(1)
        
        # Thread count
        if 'OMP_NUM_THREADS' in content:
            config['threads'] = int(re.search(r'OMP_NUM_THREADS=(\d+)', content).group(1))
        elif 'SBATCH --cpus-per-task' in content:
            config['threads'] = int(re.search(r'--cpus-per-task=(\d+)', content).group(1))
        
        # Placer engine (from OpenROAD script)
        if 'global_placement' in content:
            config['placer_engine'] = 'RePlAce'  # Default
        
        # Router engine
        if 'detailed_route' in content:
            config['router_engine'] = 'TritonRoute'  # Default
    
    return config
```

---

## Priority 2: Secure Prediction Engine

### Security Requirements

1. **Data Privacy**: User design data never leaves their environment
2. **Access Control**: Only authorized users can query predictions
3. **Audit Logging**: Track all prediction requests
4. **Encryption**: All data in transit and at rest
5. **Isolation**: Each user's data isolated from others

### Architecture: Secure Multi-Tenant Prediction

```
┌─────────────────────────────────────────────────────────┐
│ User's Private Environment (VPC)                        │
│                                                          │
│  ┌────────────────────────────────────────────────────┐ │
│  │ User's SLURM Cluster                               │ │
│  │  - User's jobs                                     │ │
│  │  - User's design data                              │ │
│  │  - SPANK plugin collects metrics                   │ │
│  └────────────────────────────────────────────────────┘ │
│                          ↓                               │
│  ┌────────────────────────────────────────────────────┐ │
│  │ User's Local Database (PostgreSQL)                 │ │
│  │  - User's job metrics ONLY                         │ │
│  │  - Encrypted at rest                               │ │
│  │  - No external access                              │ │
│  └────────────────────────────────────────────────────┘ │
│                          ↓                               │
│  ┌────────────────────────────────────────────────────┐ │
│  │ User's Prediction API (Private)                    │ │
│  │  - Runs in user's VPC                              │ │
│  │  - Trained on user's data ONLY                     │ │
│  │  - No external access                              │ │
│  │  - JWT authentication                              │ │
│  └────────────────────────────────────────────────────┘ │
│                                                          │
└─────────────────────────────────────────────────────────┘

NO DATA LEAVES USER'S ENVIRONMENT
```

### Implementation: Secure Prediction API

```python
# prediction/secure_api.py

from fastapi import FastAPI, Depends, HTTPException, status
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from jose import JWTError, jwt
from datetime import datetime, timedelta
import logging

app = FastAPI(title="HPC Resource Prediction API (Secure)")

# Security configuration
SECRET_KEY = os.getenv("API_SECRET_KEY")  # From AWS Secrets Manager
ALGORITHM = "HS256"
ACCESS_TOKEN_EXPIRE_MINUTES = 30

security = HTTPBearer()

# Audit logging
audit_logger = logging.getLogger("audit")
audit_logger.setLevel(logging.INFO)
handler = logging.FileHandler("/var/log/prediction-api/audit.log")
audit_logger.addHandler(handler)

# Authentication
def verify_token(credentials: HTTPAuthorizationCredentials = Depends(security)):
    """Verify JWT token"""
    try:
        token = credentials.credentials
        payload = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
        username = payload.get("sub")
        if username is None:
            raise HTTPException(status_code=401, detail="Invalid token")
        return username
    except JWTError:
        raise HTTPException(status_code=401, detail="Invalid token")

# Prediction endpoint with security
@app.post("/predict")
async def predict_resources(
    features: DesignFeatures,
    username: str = Depends(verify_token)
):
    """
    Predict resource requirements (SECURE)
    
    Security features:
    - JWT authentication required
    - Audit logging
    - Rate limiting
    - Input validation
    - No data persistence
    """
    
    # Audit log
    audit_logger.info(f"Prediction request from {username} at {datetime.utcnow()}")
    audit_logger.info(f"  Design: {features.cell_count} cells, {features.clock_freq_mhz} MHz")
    
    # Input validation
    if features.cell_count < 0 or features.cell_count > 10000000:
        raise HTTPException(status_code=400, detail="Invalid cell count")
    
    if features.clock_freq_mhz < 1 or features.clock_freq_mhz > 5000:
        raise HTTPException(status_code=400, detail="Invalid frequency")
    
    # Load user's private model (trained on their data only)
    model_path = f"/secure/models/{username}/model.pkl"
    if not os.path.exists(model_path):
        raise HTTPException(status_code=404, detail="Model not found for user")
    
    predictor = ResourcePredictor.load(model_path)
    
    # Make prediction
    predictions = []
    for stage in ['synthesis', 'placement', 'routing']:
        pred = predictor.predict(stage, features.dict(), {'threads': 4})
        predictions.append({
            'stage': stage,
            'cpu_cores': pred['cpu_cores'],
            'memory_gb': pred['memory_gb'],
            'duration_sec': pred['duration_sec']
        })
    
    # Audit log result
    audit_logger.info(f"  Prediction completed successfully")
    
    return {
        'predictions': predictions,
        'model_version': predictor.version,
        'timestamp': datetime.utcnow().isoformat()
    }

# Health check (no auth required)
@app.get("/health")
async def health_check():
    return {"status": "healthy", "timestamp": datetime.utcnow().isoformat()}

# Token generation (for initial setup)
@app.post("/token")
async def login(username: str, password: str):
    """Generate JWT token (authenticate user)"""
    # Verify credentials (use AWS Cognito or similar in production)
    if not verify_credentials(username, password):
        raise HTTPException(status_code=401, detail="Invalid credentials")
    
    # Create token
    access_token_expires = timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES)
    access_token = create_access_token(
        data={"sub": username}, expires_delta=access_token_expires
    )
    
    audit_logger.info(f"Token generated for {username}")
    
    return {"access_token": access_token, "token_type": "bearer"}
```

### Deployment: Secure Configuration

```yaml
# aws/cluster-config-secure.yaml

# Network isolation
HeadNode:
  Networking:
    SubnetId: subnet-PRIVATE  # Private subnet, no internet access
  SecurityGroups:
    - sg-RESTRICTIVE  # Only allow internal VPC traffic

# Encryption
SharedStorage:
  - MountDir: /shared
    Name: shared-efs
    StorageType: Efs
    EfsSettings:
      Encrypted: true  # Encryption at rest
      KmsKeyId: arn:aws:kms:region:account:key/KEY-ID

# Database encryption
# In RDS configuration:
# - StorageEncrypted: true
# - KmsKeyId: arn:aws:kms:region:account:key/KEY-ID

# API security
# Environment variables from AWS Secrets Manager:
# - API_SECRET_KEY
# - DB_PASSWORD
# - JWT_SECRET
```

### Security Checklist

- [ ] **Network Isolation**
  - [ ] Deploy in private VPC
  - [ ] No public internet access
  - [ ] Security groups restrict to internal traffic only

- [ ] **Data Encryption**
  - [ ] Database encrypted at rest (RDS encryption)
  - [ ] EFS encrypted at rest
  - [ ] TLS for all API communication
  - [ ] Secrets in AWS Secrets Manager

- [ ] **Access Control**
  - [ ] JWT authentication for API
  - [ ] IAM roles for AWS resources
  - [ ] Principle of least privilege
  - [ ] MFA for admin access

- [ ] **Audit & Monitoring**
  - [ ] All API requests logged
  - [ ] CloudWatch monitoring
  - [ ] Alerts for suspicious activity
  - [ ] Regular security audits

- [ ] **Data Privacy**
  - [ ] Each user's data isolated
  - [ ] No cross-user data access
  - [ ] Logs contain no sensitive data
  - [ ] Models trained per-user

---

## Summary

### Priority 1: Complete Parameters ✅

**Current**: 17 parameters collected  
**Target**: 40+ parameters collected  
**Implementation**: 3 phases over 2 weeks

**Key Additions**:
- Timing parameters (slack, uncertainty)
- Power parameters (gating, multi-Vt)
- Tool configurations (versions, engines)
- Stage-specific metrics (wirelength, congestion, DRC)
- Enhanced resource metrics (page faults, IOPS)

### Priority 2: Secure Prediction ✅

**Architecture**: Private deployment in user's VPC  
**Security**: JWT auth, encryption, audit logging, isolation  
**Privacy**: No data leaves user's environment

**Key Features**:
- Per-user models (trained on their data only)
- JWT authentication
- Audit logging
- Encrypted storage
- Network isolation
- No external data transmission

---

## Next Steps

1. **Implement enhanced log parsing** (Week 1)
2. **Update database schema** for new parameters (Week 1)
3. **Deploy secure prediction API** (Week 2)
4. **Test with real OpenROAD jobs** on AWS (Week 2-3)
5. **Validate parameter collection** completeness (Week 3)
6. **Security audit** (Week 4)
