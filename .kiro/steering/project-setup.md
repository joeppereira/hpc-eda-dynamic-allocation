---
inclusion: always
---

# HPC Resource Optimization Project Setup

## Project Context

This project implements an end-to-end system for optimizing HPC/EDA workload resource allocation on AWS Parallel Cluster using SLURM scheduling and SPANK plugin monitoring.

## Key Technologies

- **Monitoring**: Python psutil for local testing, SPANK plugin for SLURM
- **Database**: SQLite for local, PostgreSQL/RDS for production
- **ML Model**: scikit-learn Ridge regression (baseline)
- **API**: FastAPI for prediction service
- **Workload**: OpenROAD (EDA digital design flow)

## Project Structure

```
.
├── monitoring/           # Resource monitoring (SPANK simulator)
├── database/            # Schema and data import
├── prediction/          # ML model and API
├── scripts/             # Test and utility scripts
├── data/
│   ├── metrics/        # Collected job metrics (JSON)
│   ├── temp/           # Temporary files
│   └── results/        # Analysis outputs
└── .kiro/
    ├── specs/          # Project specifications
    └── steering/       # Project guidelines
```

## Development Workflow

### Today (Local Testing)
1. Run simulated OpenROAD jobs
2. Collect metrics via monitoring script
3. Import to database
4. Train regression model
5. Test predictions

### Tomorrow (Production)
1. Deploy AWS Parallel Cluster
2. Install SPANK plugin
3. Run real workloads
4. Validate predictions
5. Test dynamic allocation

## Code Style Guidelines

- Python: Follow PEP 8
- Type hints for function signatures
- Docstrings for all public functions
- Error handling with try/except
- Logging instead of print for production code

## Testing Approach

- Local simulation before cluster deployment
- Incremental validation (monitor → database → model → API)
- Start with small datasets (5-10 jobs)
- Scale to production (50-100 jobs)

## Key Files

- `scripts/run_local_test.sh` - Complete local test flow
- `monitoring/resource_monitor.py` - Resource monitoring
- `database/schema.py` - Database schema
- `prediction/model.py` - Ridge regression model
- `prediction/api.py` - FastAPI prediction service
