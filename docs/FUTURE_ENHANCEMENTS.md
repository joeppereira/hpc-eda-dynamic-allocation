# Future Enhancements - Scalable Architecture

## Current Architecture (v1.0)

```
Head Node:
├── SQLite Database (/shared/hpc_metrics.db)
├── Prediction API (FastAPI)
└── ML Model (in-memory)

Limitations:
- Data lost if head node terminated
- Database on head node (I/O load)
- Model training on head node (CPU load)
```

## Proposed Architecture (v2.0)

### Design Principles
1. **Data Persistence**: Survive head node termination
2. **Offload Processing**: Move heavy operations off head node
3. **Clean Separation**: Decouple data, inference, and training
4. **Backward Compatible**: Keep existing system working

---

## Enhancement 1: S3-Based Data Storage

### Current (SQLite)
```
/shared/hpc_metrics.db (local file)
```

### Proposed (JSON + S3)
```
Data Flow:
Job completes → Write JSON to /shared/metrics/job_12345.json
              → Async sync to S3
              → Head node reads from S3 on startup

S3 Structure:
s3://bucket/hpc-metrics/
├── jobs/
│   ├── 2024-11-13/
│   │   ├── job_00001.json
│   │   ├── job_00002.json
│   │   └── ...
│   └── 2024-11-14/
│       └── ...
├── aggregated/
│   ├── daily_summary_2024-11-13.json
│   └── weekly_summary_2024-W46.json
└── models/
    ├── resource_predictor_v1.pkl
    └── resource_predictor_v2.pkl
```

### Benefits
- ✅ Data survives head node termination
- ✅ No database I/O on head node
- ✅ Simple JSON files (easy to inspect/debug)
- ✅ Automatic versioning with S3
- ✅ Can process data offline

### Implementation
```python
# prediction/storage/s3_backend.py
class S3MetricsStore:
    def __init__(self, bucket, prefix="hpc-metrics"):
        self.bucket = bucket
        self.prefix = prefix
        self.local_cache = "/shared/metrics-cache"
    
    def store_job_metrics(self, job_id, metrics):
        """Store job metrics to S3"""
        date = datetime.now().strftime("%Y-%m-%d")
        key = f"{self.prefix}/jobs/{date}/job_{job_id}.json"
        
        # Write locally first
        local_file = f"{self.local_cache}/{date}/job_{job_id}.json"
        os.makedirs(os.path.dirname(local_file), exist_ok=True)
        with open(local_file, 'w') as f:
            json.dump(metrics, f)
        
        # Async upload to S3
        self.s3.upload_file(local_file, self.bucket, key)
    
    def query_similar_jobs(self, design_name, gates, tolerance=0.3):
        """Query S3 for similar jobs"""
        # Check local cache first
        cached = self._check_cache(design_name, gates)
        if cached:
            return cached
        
        # Query S3 (use S3 Select for efficiency)
        results = self._s3_select_query(design_name, gates, tolerance)
        
        # Update cache
        self._update_cache(results)
        return results
```

---

## Enhancement 2: Offline Model Training

### Current (On Head Node)
```
Head Node:
├── Collect data
├── Train model  ← CPU intensive
└── Serve predictions
```

### Proposed (Separate Training)
```
Head Node:
├── Collect data → S3
└── Serve predictions (lightweight inference)

Offline (Laptop/EC2/Lambda):
├── Download data from S3
├── Train model (heavy computation)
├── Upload model to S3
└── Head node downloads new model
```

### Benefits
- ✅ No training load on head node
- ✅ Can use powerful instances for training
- ✅ Train on schedule (nightly/weekly)
- ✅ Version control for models
- ✅ A/B testing of models

### Implementation

**Training Script (Run Offline)**
```python
# scripts/train_model_offline.py
import boto3
import pandas as pd
from prediction.model import ResourcePredictor

def train_from_s3(bucket, output_bucket):
    """Train model from S3 data"""
    s3 = boto3.client('s3')
    
    # Download all job data
    print("Downloading data from S3...")
    jobs = []
    paginator = s3.get_paginator('list_objects_v2')
    for page in paginator.paginate(Bucket=bucket, Prefix='hpc-metrics/jobs/'):
        for obj in page.get('Contents', []):
            data = s3.get_object(Bucket=bucket, Key=obj['Key'])
            jobs.append(json.loads(data['Body'].read()))
    
    # Convert to DataFrame
    df = pd.DataFrame(jobs)
    print(f"Loaded {len(df)} jobs")
    
    # Train model
    print("Training model...")
    predictor = ResourcePredictor()
    predictor.train(df)
    
    # Save model
    model_file = f"resource_predictor_{datetime.now().strftime('%Y%m%d_%H%M%S')}.pkl"
    predictor.save(model_file)
    
    # Upload to S3
    print(f"Uploading model to S3...")
    s3.upload_file(model_file, output_bucket, f'hpc-metrics/models/{model_file}')
    
    # Update "latest" pointer
    s3.put_object(
        Bucket=output_bucket,
        Key='hpc-metrics/models/latest.txt',
        Body=model_file
    )
    
    print(f"✓ Model trained and uploaded: {model_file}")

# Run from laptop or EC2
if __name__ == "__main__":
    train_from_s3(
        bucket="parallelcluster-xxx",
        output_bucket="parallelcluster-xxx"
    )
```

**Lightweight Inference (On Head Node)**
```python
# prediction/inference_api.py
class LightweightPredictor:
    def __init__(self, s3_bucket):
        self.s3_bucket = s3_bucket
        self.model = None
        self.model_version = None
        self.load_model()
    
    def load_model(self):
        """Load latest model from S3"""
        s3 = boto3.client('s3')
        
        # Get latest model version
        latest = s3.get_object(
            Bucket=self.s3_bucket,
            Key='hpc-metrics/models/latest.txt'
        )
        model_file = latest['Body'].read().decode()
        
        # Download if not cached or version changed
        if self.model_version != model_file:
            local_path = f"/tmp/{model_file}"
            s3.download_file(
                self.s3_bucket,
                f'hpc-metrics/models/{model_file}',
                local_path
            )
            self.model = ResourcePredictor.load(local_path)
            self.model_version = model_file
            print(f"✓ Loaded model: {model_file}")
    
    def predict(self, design_features):
        """Fast inference only"""
        # Check for model updates periodically
        if self._should_refresh():
            self.load_model()
        
        return self.model.predict(design_features)
```

---

## Enhancement 3: Hybrid Storage Strategy

### Best of Both Worlds

```
┌─────────────────────────────────────────────────────────┐
│                    Storage Strategy                      │
├─────────────────────────────────────────────────────────┤
│                                                           │
│  Recent Data (Last 7 days):                             │
│  ├── Local JSON files (/shared/metrics/)                │
│  └── Fast queries (no S3 latency)                       │
│                                                           │
│  Historical Data (> 7 days):                            │
│  ├── S3 only (s3://bucket/hpc-metrics/)                 │
│  └── Query on demand (cached locally)                   │
│                                                           │
│  Aggregated Summaries:                                  │
│  ├── Pre-computed statistics                            │
│  └── Fast lookups for common queries                    │
│                                                           │
└─────────────────────────────────────────────────────────┘
```

### Implementation
```python
class HybridStorage:
    def __init__(self):
        self.local_store = LocalJSONStore("/shared/metrics")
        self.s3_store = S3MetricsStore("bucket")
        self.cache = LRUCache(maxsize=1000)
    
    def query_similar_jobs(self, design_name, gates):
        # 1. Check cache
        cache_key = f"{design_name}_{gates}"
        if cache_key in self.cache:
            return self.cache[cache_key]
        
        # 2. Query recent local data (fast)
        recent = self.local_store.query(design_name, gates, days=7)
        
        # 3. If not enough data, query S3 (slower)
        if len(recent) < 3:
            historical = self.s3_store.query(design_name, gates)
            recent.extend(historical)
        
        # 4. Cache result
        self.cache[cache_key] = recent
        return recent
```

---

## Migration Path

### Phase 1: Current System (Now)
```
✓ SQLite database
✓ On-head-node training
✓ Simple, works immediately
```

### Phase 2: Add S3 Backup (Easy)
```
→ Keep SQLite
→ Add periodic S3 sync
→ Restore from S3 on startup
```

### Phase 3: Hybrid Storage (Medium)
```
→ JSON files + S3
→ Keep SQLite for compatibility
→ Gradual migration
```

### Phase 4: Full S3 + Offline Training (Advanced)
```
→ Remove SQLite
→ S3-only storage
→ Offline model training
→ Lightweight inference
```

---

## Configuration

### Environment Variables
```bash
# Storage backend
STORAGE_BACKEND=sqlite  # or: json, s3, hybrid

# S3 configuration
S3_BUCKET=parallelcluster-xxx
S3_PREFIX=hpc-metrics

# Model configuration
MODEL_SOURCE=local  # or: s3
MODEL_UPDATE_INTERVAL=3600  # seconds

# Cache configuration
LOCAL_CACHE_DIR=/shared/metrics-cache
CACHE_RETENTION_DAYS=7
```

### Config File
```yaml
# config/storage.yaml
storage:
  backend: hybrid
  
  local:
    path: /shared/metrics
    retention_days: 7
  
  s3:
    bucket: parallelcluster-xxx
    prefix: hpc-metrics
    sync_interval: 300  # seconds
  
model:
  source: s3
  update_check_interval: 3600
  fallback_to_local: true

cache:
  enabled: true
  max_size: 1000
  ttl: 3600
```

---

## Summary

**Current System (v1.0):**
- ✅ Simple, works now
- ✅ No external dependencies
- ⚠️ Data lost on head node termination
- ⚠️ Training load on head node

**Future System (v2.0):**
- ✅ Data survives head node loss
- ✅ Offloaded training
- ✅ Scalable storage
- ✅ Clean separation of concerns
- ✅ Backward compatible

**Recommendation:** 
Keep current system for now, design with clean interfaces to enable future migration without breaking changes.
