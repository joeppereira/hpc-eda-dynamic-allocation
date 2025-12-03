# SLURM REST API Guide for ParallelCluster

## Overview

This guide shows how to enable and use the native SLURM REST API (`slurmrestd`) on AWS ParallelCluster, allowing users to submit jobs via HTTPS instead of SSH.

## What is slurmrestd?

- **Official SLURM REST API daemon** (included with SLURM 20.02+)
- OpenAPI-compliant REST interface
- Same API that AWS PCS uses under the hood
- Can be enabled on any SLURM cluster, including ParallelCluster

## Architecture Comparison

### Traditional SSH-Based Submission
```
User Laptop → SSH → Head Node → sbatch → SLURM → SPANK Plugin
                                                      ↓
                                                  setrlimit()
```

### REST API-Based Submission
```
User Laptop → HTTPS → slurmrestd → SLURM → SPANK Plugin
                                               ↓
                                           setrlimit()
```

**Key Point:** SPANK plugin works identically regardless of submission method!

---

## Enabling on ParallelCluster

### Step 1: Add to Cluster Configuration

```yaml
# cluster-config.yaml
HeadNode:
  InstanceType: c5.xlarge
  CustomActions:
    OnNodeConfigured:
      Script: s3://your-bucket/scripts/enable_slurm_rest_api.sh
```

### Step 2: Enable slurmrestd

```bash
# On head node
./aws/enable_slurm_rest_api.sh
```

This script:
1. Installs `slurm-slurmrestd` package
2. Creates systemd service
3. Starts API on port 6820
4. Tests endpoint

### Step 3: Configure Security Group

Add inbound rule to head node security group:
- **Type:** Custom TCP
- **Port:** 6820
- **Source:** Your IP or VPC CIDR

---

## API Endpoints

### Base URL
```
http://head-node-ip:6820/slurm/v0.0.40
```

### Key Endpoints

| Method | Endpoint | Description |
|--------|----------|-------------|
| POST | `/job/submit` | Submit new job |
| GET | `/jobs` | List all jobs |
| GET | `/job/{job_id}` | Get job details |
| DELETE | `/job/{job_id}` | Cancel job |
| GET | `/nodes` | List cluster nodes |
| GET | `/partitions` | List partitions |
| GET | `/diag` | Cluster diagnostics |

### API Documentation
```bash
# Get OpenAPI spec
curl http://head-node:6820/openapi/v3
```

---

## Job Submission Examples

### 1. Simple Job (curl)

```bash
curl -X POST http://head-node:6820/slurm/v0.0.40/job/submit \
  -H "Content-Type: application/json" \
  -H "X-SLURM-USER-NAME: ec2-user" \
  -d '{
    "job": {
      "name": "test_job",
      "partition": "compute",
      "script": "#!/bin/bash\necho Hello from REST API\nsleep 10"
    }
  }'
```

### 2. Job with Resource Specs (Python)

```python
import requests

url = "http://head-node:6820/slurm/v0.0.40/job/submit"
headers = {
    "Content-Type": "application/json",
    "X-SLURM-USER-NAME": "ec2-user"
}

job_spec = {
    "job": {
        "name": "resource_job",
        "partition": "compute",
        "nodes": [1, 1],  # min, max
        "tasks": 4,
        "memory_per_node": {"number": 8192, "set": True},
        "time_limit": {"number": 60, "set": True},  # minutes
        "script": "#!/bin/bash\nsrun hostname\nsleep 30"
    }
}

response = requests.post(url, json=job_spec, headers=headers)
job_id = response.json()["job_id"]
print(f"Job submitted: {job_id}")
```

### 3. OpenROAD Job with SPANK Dynamic Allocation

```python
import requests

url = "http://head-node:6820/slurm/v0.0.40/job/submit"
headers = {
    "Content-Type": "application/json",
    "X-SLURM-USER-NAME": "ec2-user"
}

gates = 50000

# SPANK plugin will read --gates option and set memory limit
job_spec = {
    "job": {
        "name": "openroad_rest",
        "partition": "compute",
        "nodes": [1, 1],
        "tasks": 2,
        "memory_per_node": {"number": 8192, "set": True},
        "environment": {"GATES": str(gates)},
        "script": f"""#!/bin/bash
#SBATCH --gates={gates}

echo "Running OpenROAD with {gates} gates"
python3 /shared/scripts/simulate_openroad_job.py --gates {gates}
"""
    }
}

response = requests.post(url, json=job_spec, headers=headers)
job_id = response.json()["job_id"]
print(f"OpenROAD job submitted: {job_id}")
```

---

## Monitoring Jobs

### Get Job Status

```python
import requests

job_id = 12345
url = f"http://head-node:6820/slurm/v0.0.40/job/{job_id}"
headers = {"X-SLURM-USER-NAME": "ec2-user"}

response = requests.get(url, headers=headers)
job_info = response.json()

for job in job_info["jobs"]:
    print(f"Job {job['job_id']}: {job['job_state']}")
    print(f"  Start: {job.get('start_time', 'N/A')}")
    print(f"  Memory: {job.get('memory_per_node', 'N/A')} MB")
```

### List All Jobs

```python
url = "http://head-node:6820/slurm/v0.0.40/jobs"
headers = {"X-SLURM-USER-NAME": "ec2-user"}

response = requests.get(url, headers=headers)
jobs = response.json()["jobs"]

for job in jobs:
    print(f"{job['job_id']}: {job['name']} - {job['job_state']}")
```

### Cancel Job

```python
job_id = 12345
url = f"http://head-node:6820/slurm/v0.0.40/job/{job_id}"
headers = {"X-SLURM-USER-NAME": "ec2-user"}

response = requests.delete(url, headers=headers)
print(f"Job {job_id} cancelled")
```

---

## Authentication

### Local Auth (Development)

```bash
# Start with local auth (trust-based)
slurmrestd -a rest_auth/local 0.0.0.0:6820

# User specified in header
curl -H "X-SLURM-USER-NAME: ec2-user" ...
```

**Pros:** Simple, no token management  
**Cons:** Not secure, trust-based

### JWT Auth (Production)

```bash
# Generate JWT token
scontrol token username=ec2-user

# Start with JWT auth
slurmrestd -a rest_auth/jwt 0.0.0.0:6820

# Use token in requests
curl -H "X-SLURM-USER-TOKEN: eyJ..." ...
```

**Pros:** Secure, token-based  
**Cons:** Token management required

### AWS PCS Approach

AWS PCS wraps slurmrestd with:
- API Gateway for HTTPS
- IAM authentication
- Rate limiting
- Logging

You can replicate this with:
```
User → API Gateway → Lambda → slurmrestd on head node
         ↓
      IAM Auth
```

---

## Integration with SPANK Plugin

### How It Works Together

1. **User submits via REST API:**
   ```python
   job_spec = {
       "job": {
           "script": "#!/bin/bash\n#SBATCH --gates=50000\n..."
       }
   }
   ```

2. **slurmrestd converts to sbatch:**
   ```bash
   # Equivalent to:
   sbatch --gates=50000 script.sh
   ```

3. **SLURM schedules job, SPANK plugin runs:**
   ```c
   // In spank_dynamic_alloc.c
   int slurm_spank_task_post_fork() {
       // Read --gates=50000
       // Calculate memory: 2000 + (50000 * 0.08) = 6000 MB
       // Set limit: setrlimit(6000 * 1.2 * 1024 * 1024)
   }
   ```

**Result:** Dynamic allocation works identically whether job submitted via SSH or REST API!

---

## Use Cases

### 1. Web Dashboard

```python
# Flask app for job submission
from flask import Flask, request, jsonify
import requests

app = Flask(__name__)
SLURM_API = "http://head-node:6820/slurm/v0.0.40"

@app.route("/submit", methods=["POST"])
def submit_job():
    data = request.json
    
    job_spec = {
        "job": {
            "name": data["name"],
            "script": data["script"]
        }
    }
    
    response = requests.post(
        f"{SLURM_API}/job/submit",
        json=job_spec,
        headers={"X-SLURM-USER-NAME": data["user"]}
    )
    
    return jsonify(response.json())
```

### 2. CI/CD Integration

```yaml
# GitHub Actions
- name: Submit SLURM job
  run: |
    curl -X POST $SLURM_API/job/submit \
      -H "X-SLURM-USER-NAME: ci-user" \
      -d '{"job": {"script": "#!/bin/bash\nmake test"}}'
```

### 3. Mobile App

```swift
// iOS app
func submitJob(script: String) {
    let url = URL(string: "http://cluster:6820/slurm/v0.0.40/job/submit")!
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("mobile-user", forHTTPHeaderField: "X-SLURM-USER-NAME")
    
    let jobSpec = ["job": ["script": script]]
    request.httpBody = try? JSONSerialization.data(withJSONObject: jobSpec)
    
    URLSession.shared.dataTask(with: request) { data, response, error in
        // Handle response
    }.resume()
}
```

---

## Comparison: ParallelCluster vs AWS PCS

| Feature | ParallelCluster + slurmrestd | AWS PCS |
|---------|----------------------------|---------|
| **REST API** | ✅ Manual setup | ✅ Built-in |
| **Authentication** | Local/JWT | IAM |
| **HTTPS** | Manual (nginx/ALB) | Built-in |
| **API Gateway** | Manual | Built-in |
| **Cost** | Cluster only | Cluster + API calls |
| **Setup Time** | 10 minutes | Immediate |
| **Flexibility** | Full control | AWS-managed |

---

## Security Best Practices

### 1. Use HTTPS

```bash
# Put nginx in front of slurmrestd
upstream slurmrestd {
    server localhost:6820;
}

server {
    listen 443 ssl;
    ssl_certificate /path/to/cert.pem;
    ssl_certificate_key /path/to/key.pem;
    
    location /slurm/ {
        proxy_pass http://slurmrestd;
    }
}
```

### 2. Enable JWT Authentication

```bash
# Generate JWT secret
openssl rand -base64 32 > /etc/slurm/jwt_hs256.key
chmod 600 /etc/slurm/jwt_hs256.key

# Configure slurmctld
echo "AuthAltTypes=auth/jwt" >> /etc/slurm/slurm.conf

# Restart services
sudo systemctl restart slurmctld
sudo systemctl restart slurmrestd
```

### 3. Restrict Access

```bash
# Firewall rules
sudo firewall-cmd --add-rich-rule='rule family="ipv4" source address="10.0.0.0/16" port port="6820" protocol="tcp" accept'
```

---

## Testing

### Quick Test Script

```bash
#!/bin/bash
# Test SLURM REST API

API="http://localhost:6820/slurm/v0.0.40"
USER="ec2-user"

echo "1. Testing API availability..."
curl -s $API/diag | jq '.meta'

echo -e "\n2. Submitting test job..."
JOB_ID=$(curl -s -X POST $API/job/submit \
  -H "Content-Type: application/json" \
  -H "X-SLURM-USER-NAME: $USER" \
  -d '{"job": {"script": "#!/bin/bash\nsleep 10"}}' \
  | jq -r '.job_id')

echo "Job ID: $JOB_ID"

echo -e "\n3. Checking job status..."
curl -s $API/job/$JOB_ID \
  -H "X-SLURM-USER-NAME: $USER" \
  | jq '.jobs[0] | {id: .job_id, state: .job_state}'

echo -e "\n4. Listing all jobs..."
curl -s $API/jobs \
  -H "X-SLURM-USER-NAME: $USER" \
  | jq '.jobs[] | {id: .job_id, name: .name, state: .job_state}'
```

---

## Troubleshooting

### API Not Responding

```bash
# Check service status
sudo systemctl status slurmrestd

# Check logs
sudo journalctl -u slurmrestd -f

# Test locally
curl http://localhost:6820/slurm/v0.0.40/diag
```

### Authentication Errors

```bash
# Verify user exists
id ec2-user

# Check SLURM user
sacctmgr show user ec2-user

# Test with different auth
slurmrestd -a rest_auth/local -vvv 0.0.0.0:6820
```

### Job Submission Fails

```bash
# Check SLURM controller
scontrol ping

# Verify partition
sinfo

# Test with sbatch
sbatch --wrap="sleep 10"
```

---

## Summary

### Key Points

1. **slurmrestd is the native SLURM REST API** - same as AWS PCS uses
2. **Can be enabled on ParallelCluster** in ~10 minutes
3. **SPANK plugin works identically** with REST API or SSH submission
4. **Enables modern integrations** - web apps, mobile, CI/CD
5. **Production-ready** with JWT auth and HTTPS

### When to Use

- ✅ Building web dashboards
- ✅ Mobile app integration
- ✅ CI/CD pipelines
- ✅ External system integration
- ✅ No SSH access for users

### When SSH is Fine

- Traditional HPC workflows
- Command-line users
- Internal cluster only
- Simple use cases

---

## Resources

- [SLURM REST API Documentation](https://slurm.schedmd.com/rest.html)
- [slurmrestd Man Page](https://slurm.schedmd.com/slurmrestd.html)
- [OpenAPI Specification](https://slurm.schedmd.com/rest_api.html)
- [AWS PCS Documentation](https://docs.aws.amazon.com/pcs/)

---

## Next Steps

1. Enable slurmrestd on your cluster: `./aws/enable_slurm_rest_api.sh`
2. Test with Python client: `python examples/submit_job_via_rest_api.py`
3. Submit OpenROAD job via API: `python examples/submit_job_via_rest_api.py --example openroad`
4. Build your web dashboard or integration!
