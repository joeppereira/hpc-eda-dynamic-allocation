#!/usr/bin/env python3
"""
Generate AWS Architecture Diagram for ML-Driven HPC Resource Optimization System
Based on Figure 1 from BLOG_POST_ARCHITECTURE_DIAGRAM.md
"""

from diagrams import Diagram, Cluster, Edge
from diagrams.aws.compute import EC2, Compute
from diagrams.aws.storage import EFS, FSx, FsxForLustre, S3
from diagrams.aws.database import RDS
from diagrams.aws.management import Cloudwatch
from diagrams.aws.security import IAM
from diagrams.aws.ml import SagemakerModel
from diagrams.aws.integration import SimpleNotificationServiceSns as Lambda

def generate_hpc_architecture():
    """Generate the HPC architecture diagram"""
    
    graph_attr = {
        "fontsize": "14",
        "bgcolor": "white",
        "pad": "0.5",
    }
    
    with Diagram(
        "ML-Driven HPC Resource Optimization System",
        filename="docs/diagrams/hpc-architecture",
        direction="TB",
        show=False,
        graph_attr=graph_attr
    ):
        
        with Cluster("AWS Region (us-east-1) - VPC"):
            
            # Head Node Cluster
            with Cluster("Head Node (EC2)"):
                slurm_controller = Compute("SLURM\nController\n(slurmctld)")
                job_plugin = Lambda("Job Submit\nPlugin\n(Lua)")
                prediction_api = SagemakerModel("Prediction API\n(ML Engine)")
                dashboard = Cloudwatch("Dashboard\n(Web UI)")
                metrics_db = RDS("Metrics DB\n(SQLite/RDS)")
                
                # Connections within head node
                job_plugin >> Edge(label="query") >> prediction_api
                job_plugin >> Edge(label="submit") >> slurm_controller
                prediction_api >> Edge(label="history") >> metrics_db
            
            # Compute Nodes Cluster
            with Cluster("Compute Nodes (Auto Scaling Group)"):
                compute_1 = EC2("Compute-1\nslurmd\nMonitor\n(c8/r8/m8)")
                compute_2 = EC2("Compute-2\nslurmd\nMonitor\n(c8/r8/m8)")
                compute_n = EC2("Compute-N\nslurmd\nMonitor\n(c8/r8/m8)")
                compute_nodes = [compute_1, compute_2, compute_n]
            
            # Shared Storage
            with Cluster("Shared Storage (Choose One)"):
                efs = EFS("Amazon EFS\n(General NFS)")
                fsx_lustre = FsxForLustre("FSx Lustre\n(HPC Optimized)")
                fsx_ontap = FSx("FSx ONTAP\n(Enterprise)")
                storage_options = [efs, fsx_lustre, fsx_ontap]
            
            # AWS Services
            with Cluster("AWS Services"):
                s3 = S3("S3\n(Backups)")
                rds_prod = RDS("RDS\n(Production DB)")
                cloudwatch = Cloudwatch("CloudWatch\n(Monitoring)")
                iam = IAM("IAM\n(Security)")
            
            # Main data flows
            # 1. Job dispatch from SLURM to compute nodes
            slurm_controller >> Edge(label="dispatch", color="blue") >> compute_nodes
            
            # 2. Storage connections (dashed to show optional/shared)
            for node in compute_nodes:
                node >> Edge(style="dashed", color="gray") >> storage_options
            
            slurm_controller >> Edge(style="dashed", color="gray") >> storage_options
            
            # 3. Metrics feedback loop (green for learning)
            for node in compute_nodes:
                node >> Edge(label="metrics", color="green") >> metrics_db
            
            # 4. AWS Services connections
            for node in compute_nodes:
                node >> Edge(style="dotted", color="orange") >> cloudwatch
            
            slurm_controller >> Edge(style="dotted", color="orange") >> cloudwatch
            
            # 5. Backup to S3
            for node in compute_nodes:
                node >> Edge(style="dotted", color="purple") >> s3
            
            # 6. Database scaling option
            metrics_db >> Edge(label="scale", style="dashed") >> rds_prod
    
    print("✓ Diagram generated: docs/diagrams/hpc-architecture.png")
    print("✓ Location: /Users/spereirj/dynamic_allocation/docs/diagrams/")

if __name__ == "__main__":
    generate_hpc_architecture()
