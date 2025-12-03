#!/usr/bin/env python3
"""
Submit SLURM jobs via native REST API (slurmrestd)
Works on ParallelCluster with slurmrestd enabled
"""

import requests
import json
import time
import argparse


class SlurmRestClient:
    """Client for SLURM REST API"""
    
    def __init__(self, base_url="http://localhost:6820", api_version="v0.0.40", user="ec2-user"):
        self.base_url = base_url
        self.api_version = api_version
        self.user = user
        self.headers = {
            "Content-Type": "application/json",
            "X-SLURM-USER-NAME": user
        }
    
    def submit_job(self, script, name="rest_job", partition="compute", 
                   memory_mb=4096, cpus=1, custom_env=None):
        """Submit a job via REST API"""
        
        url = f"{self.base_url}/slurm/{self.api_version}/job/submit"
        
        job_spec = {
            "job": {
                "name": name,
                "partition": partition,
                "nodes": [1, 1],  # min, max
                "tasks": cpus,
                "memory_per_node": {"number": memory_mb, "set": True},
                "current_working_directory": "/shared",
                "standard_output": f"/shared/logs/{name}-%j.out",
                "standard_error": f"/shared/logs/{name}-%j.err",
                "script": script
            }
        }
        
        # Add custom environment variables
        if custom_env:
            job_spec["job"]["environment"] = custom_env
        
        response = requests.post(url, json=job_spec, headers=self.headers)
        response.raise_for_status()
        
        result = response.json()
        job_id = result.get("job_id")
        
        print(f"✓ Job submitted: {job_id}")
        return job_id
    
    def get_job_info(self, job_id):
        """Get job information"""
        url = f"{self.base_url}/slurm/{self.api_version}/job/{job_id}"
        response = requests.get(url, headers=self.headers)
        response.raise_for_status()
        return response.json()
    
    def list_jobs(self):
        """List all jobs"""
        url = f"{self.base_url}/slurm/{self.api_version}/jobs"
        response = requests.get(url, headers=self.headers)
        response.raise_for_status()
        return response.json()
    
    def cancel_job(self, job_id):
        """Cancel a job"""
        url = f"{self.base_url}/slurm/{self.api_version}/job/{job_id}"
        response = requests.delete(url, headers=self.headers)
        response.raise_for_status()
        print(f"✓ Job {job_id} cancelled")
    
    def get_nodes(self):
        """Get node information"""
        url = f"{self.base_url}/slurm/{self.api_version}/nodes"
        response = requests.get(url, headers=self.headers)
        response.raise_for_status()
        return response.json()


def example_simple_job():
    """Example: Submit a simple sleep job"""
    client = SlurmRestClient()
    
    script = """#!/bin/bash
#SBATCH --job-name=simple_test
echo "Job started at $(date)"
sleep 30
echo "Job finished at $(date)"
"""
    
    job_id = client.submit_job(
        script=script,
        name="simple_test",
        memory_mb=1024,
        cpus=1
    )
    
    return job_id


def example_openroad_job_with_spank():
    """Example: Submit OpenROAD job with SPANK dynamic allocation"""
    client = SlurmRestClient()
    
    gates = 50000
    
    # Script with SPANK custom option
    script = f"""#!/bin/bash
#SBATCH --job-name=openroad_rest
#SBATCH --gates={gates}

echo "Running OpenROAD with {gates} gates"
echo "SPANK plugin will set memory limit dynamically"

# Simulate OpenROAD
python3 /shared/scripts/simulate_openroad_job.py --gates {gates}
"""
    
    job_id = client.submit_job(
        script=script,
        name="openroad_rest",
        memory_mb=8192,  # SLURM allocation (SPANK will set process limit)
        cpus=2,
        custom_env={"GATES": str(gates)}
    )
    
    return job_id


def example_monitor_job(job_id):
    """Example: Monitor job status"""
    client = SlurmRestClient()
    
    print(f"\nMonitoring job {job_id}...")
    
    while True:
        info = client.get_job_info(job_id)
        jobs = info.get("jobs", [])
        
        if not jobs:
            print("Job completed or not found")
            break
        
        job = jobs[0]
        state = job.get("job_state", "UNKNOWN")
        
        print(f"  State: {state}")
        
        if state in ["COMPLETED", "FAILED", "CANCELLED"]:
            break
        
        time.sleep(5)


def example_list_all_jobs():
    """Example: List all jobs"""
    client = SlurmRestClient()
    
    result = client.list_jobs()
    jobs = result.get("jobs", [])
    
    print(f"\nTotal jobs: {len(jobs)}")
    for job in jobs[:10]:  # Show first 10
        print(f"  {job['job_id']}: {job['name']} - {job['job_state']}")


def example_cluster_info():
    """Example: Get cluster information"""
    client = SlurmRestClient()
    
    result = client.get_nodes()
    nodes = result.get("nodes", [])
    
    print(f"\nCluster nodes: {len(nodes)}")
    for node in nodes:
        print(f"  {node['name']}: {node['state']} - "
              f"{node['cpus']} CPUs, {node['real_memory']} MB RAM")


def main():
    parser = argparse.ArgumentParser(description="Submit jobs via SLURM REST API")
    parser.add_argument("--url", default="http://localhost:6820", 
                       help="SLURM REST API base URL")
    parser.add_argument("--user", default="ec2-user", 
                       help="SLURM user name")
    parser.add_argument("--example", choices=["simple", "openroad", "list", "cluster"],
                       default="simple", help="Example to run")
    
    args = parser.parse_args()
    
    # Update client defaults
    SlurmRestClient.__init__.__defaults__ = (args.url, "v0.0.40", args.user)
    
    if args.example == "simple":
        print("=== Submitting Simple Job ===")
        job_id = example_simple_job()
        example_monitor_job(job_id)
    
    elif args.example == "openroad":
        print("=== Submitting OpenROAD Job with SPANK ===")
        job_id = example_openroad_job_with_spank()
        example_monitor_job(job_id)
    
    elif args.example == "list":
        example_list_all_jobs()
    
    elif args.example == "cluster":
        example_cluster_info()


if __name__ == "__main__":
    main()
