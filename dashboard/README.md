# HPC Resource Optimization Dashboard

Real-time operational dashboard for monitoring SLURM job resource allocation and ML-driven optimization.

## Features

### 📊 Real-Time Monitoring
- **Live Job Tracking**: Monitor active and completed jobs
- **Resource Metrics**: CPU, memory, I/O usage from SPANK plugin
- **Design Attributes**: Gate count, net count, technology parameters
- **SLURM Integration**: Job status, queue times, allocation changes

### 🎯 Optimization Visualization
- **Before/After Comparison**: Requested vs actual vs predicted resources
- **Savings Metrics**: CPU, memory, and cost savings per job
- **Trend Analysis**: Historical performance and optimization trends
- **Correlation Charts**: Design attributes vs resource requirements

### 💰 Cost Analysis
- **Real-Time Savings**: Current cost reduction from optimization
- **Projected Savings**: Annual cost impact estimates
- **Resource Efficiency**: Utilization rates and waste reduction
- **ROI Tracking**: Return on investment from ML predictions

## Quick Start

### 1. Install Dependencies

```bash
pip install -r requirements.txt
```

### 2. Set Database Path

```bash
export DB_PATH=/path/to/hpc_metrics.db
```

### 3. Start Dashboard

```bash
cd dashboard
python app.py
```

### 4. Access Dashboard

Open browser to: `http://localhost:5000`

## Dashboard Components

### Summary Statistics
- **Total Jobs**: Jobs processed in last 24 hours
- **CPU Savings**: Percentage reduction in CPU allocation
- **Memory Savings**: Percentage reduction in memory allocation
- **Cost Savings**: Dollar amount saved from optimization
- **Average Usage**: Current resource utilization metrics

### Resource Allocation Chart
Compares three allocation strategies:
- **Red (Requested)**: Initial user/default request
- **Orange (Actual)**: Real usage measured by SPANK plugin
- **Green (Predicted)**: ML model optimized allocation

### Cost Savings Timeline
Tracks savings over time:
- CPU savings percentage per job
- Memory savings percentage per job
- Trend analysis for optimization effectiveness

### Design Correlation
Scatter plot showing relationship between:
- Number of gates vs CPU usage
- Number of nets vs memory usage
- Design complexity vs runtime

### Resource Timeline
Hourly aggregated view of:
- Requested resources (baseline)
- Actual usage (SPANK monitoring)
- Predicted allocation (ML model)

### Recent Jobs Table
Detailed view of recent jobs with:
- Job ID and design name
- Design attributes (gates, nets)
- Resource comparison (requested/actual/predicted)
- Savings percentage
- Job status

## API Endpoints

### GET /api/jobs/recent
Returns last 20 jobs with full resource data

**Response:**
```json
[
  {
    "job_id": 12345,
    "design_name": "aes_cipher",
    "num_gates": 5000,
    "requested_cpu": 200,
    "actual_cpu": 85.3,
    "predicted_cpu": 95.0,
    "requested_memory_mb": 8192,
    "actual_memory": 3456,
    "predicted_memory_mb": 4096,
    "cpu_savings_percent": 52.5,
    "memory_savings_percent": 50.0,
    "status": "completed"
  }
]
```

### GET /api/stats/summary
Returns aggregated statistics for last 24 hours

**Response:**
```json
{
  "total_jobs": 150,
  "avg_cpu_actual": 78.5,
  "avg_cpu_requested": 180.0,
  "avg_cpu_predicted": 92.3,
  "cpu_savings_percent": 48.7,
  "memory_savings_percent": 45.2,
  "current_cost": 125.50,
  "optimized_cost": 68.75,
  "cost_savings": 56.75,
  "cost_savings_percent": 45.2
}
```

### GET /api/jobs/{job_id}
Returns detailed information for specific job including SPANK timeline

**Response:**
```json
{
  "job_id": 12345,
  "design_name": "aes_cipher",
  "spank_timeline": [
    {
      "timestamp": "2025-11-11T10:30:00",
      "cpu_percent": 85.3,
      "memory_mb": 3456,
      "io_read_mb": 125.5,
      "io_write_mb": 89.2
    }
  ]
}
```

### GET /api/timeline
Returns hourly aggregated resource usage

### GET /api/design/correlation
Returns design attributes vs resource usage for correlation analysis

## Integration with SLURM

### SPANK Plugin Integration

The dashboard reads real-time metrics from SPANK plugin:

```c
// SPANK plugin logs to database
spank_log_metrics(job_id, cpu_percent, memory_mb, io_stats);
```

### Job Submission with Predictions

```bash
#!/bin/bash
#SBATCH --job-name=openroad_job
#SBATCH --cpus-per-task=4
#SBATCH --mem=8G

# Get ML prediction
PREDICTED=$(curl http://localhost:8000/predict \
  -d '{"num_gates": 5000, "num_nets": 4500}')

# Extract predicted resources
PRED_CPU=$(echo $PREDICTED | jq -r '.cpu_cores')
PRED_MEM=$(echo $PREDICTED | jq -r '.memory_gb')

# Update SLURM allocation
scontrol update JobId=$SLURM_JOB_ID \
  NumCPUs=$PRED_CPU \
  MinMemoryNode=${PRED_MEM}G

# Run workload
singularity exec openroad.sif openroad -script flow.tcl
```

## Deployment

### Local Development

```bash
# Start dashboard
python dashboard/app.py

# Access at http://localhost:5000
```

### Production Deployment

```bash
# Using gunicorn
pip install gunicorn
gunicorn -w 4 -b 0.0.0.0:5000 dashboard.app:app

# Using systemd service
sudo cp dashboard/dashboard.service /etc/systemd/system/
sudo systemctl enable dashboard
sudo systemctl start dashboard
```

### AWS ParallelCluster

```bash
# On head node
cd /shared/hpc-optimization/dashboard
export DB_PATH=/shared/hpc_metrics.db
nohup python app.py > dashboard.log 2>&1 &

# Access via head node IP
# http://<head-node-ip>:5000
```

## Configuration

### Environment Variables

```bash
# Database path
export DB_PATH=/path/to/hpc_metrics.db

# Flask settings
export FLASK_ENV=production
export FLASK_HOST=0.0.0.0
export FLASK_PORT=5000

# Auto-refresh interval (seconds)
export REFRESH_INTERVAL=30
```

### Database Schema

The dashboard expects these tables:
- `job_metrics`: Main job records with resource data
- `spank_metrics`: Real-time monitoring from SPANK plugin
- `predictions`: ML model predictions and accuracy

## Monitoring & Alerts

### Key Metrics to Watch

1. **Prediction Accuracy**: Should be >80%
2. **Savings Rate**: Target 30-50% resource reduction
3. **Job Success Rate**: Should remain >95%
4. **Cost Savings**: Track monthly/annual trends

### Alert Thresholds

```python
# Add to app.py for alerting
if stats['cpu_savings_percent'] < 20:
    send_alert("Low optimization rate")

if stats['prediction_accuracy'] < 80:
    send_alert("Model needs retraining")
```

## Troubleshooting

### Dashboard Not Loading
```bash
# Check if Flask is running
ps aux | grep app.py

# Check logs
tail -f dashboard.log

# Verify database connection
sqlite3 $DB_PATH "SELECT COUNT(*) FROM job_metrics;"
```

### No Data Showing
```bash
# Verify SPANK plugin is logging
tail -f /var/log/slurm/spank_monitor.log

# Check database has recent data
sqlite3 $DB_PATH "SELECT * FROM job_metrics ORDER BY timestamp DESC LIMIT 5;"
```

### Charts Not Updating
- Check browser console for JavaScript errors
- Verify API endpoints are responding: `curl http://localhost:5000/api/stats/summary`
- Check auto-refresh is enabled (30 second interval)

## Example Screenshots

### Main Dashboard
Shows real-time statistics, resource comparison charts, and recent jobs table.

### Resource Allocation Comparison
Bar chart comparing requested (red), actual (orange), and predicted (green) resources.

### Cost Savings Timeline
Line chart showing CPU and memory savings percentage over time.

### Design Correlation
Scatter plot showing relationship between design attributes and resource usage.

## Future Enhancements

- [ ] Real-time WebSocket updates
- [ ] Custom alert configuration UI
- [ ] Export reports to PDF
- [ ] Multi-cluster support
- [ ] User authentication
- [ ] Historical data archival
- [ ] Predictive capacity planning
- [ ] Integration with AWS Cost Explorer

## License

MIT License - See LICENSE file for details

## Support

For issues or questions:
- GitHub Issues: [project-repo]/issues
- Documentation: [project-repo]/wiki
- Email: support@example.com
