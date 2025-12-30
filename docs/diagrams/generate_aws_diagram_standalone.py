#!/usr/bin/env python3
"""
AWS Architecture Diagram Generator - Standalone Version
Generate professional AWS architecture diagrams using Python

REQUIREMENTS:
- Python 3.8+
- pip install diagrams
- GraphViz installed (brew install graphviz on macOS)

USAGE:
    python generate_aws_diagram_standalone.py

OUTPUT:
    hpc-architecture.png (in current directory)
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
    """
    Generate ML-Driven HPC Resource Optimization System Architecture
    
    This creates a comprehensive AWS architecture diagram showing:
    - Head Node with SLURM, ML API, Dashboard
    - Auto-scaling compute nodes
    - Shared storage options (EFS, FSx)
    - AWS services (S3, RDS, CloudWatch, IAM)
    - Data flows and connections
    """
    
    # Graph styling
    graph_attr = {
        "fontsize": "14",
        "bgcolor": "white",
        "pad": "0.5",
    }
    
    with Diagram(
        "ML-Driven HPC Resource Optimization System",
        filename="hpc-architecture",  # Output filename (without extension)
        direction="TB",                # Top to Bottom layout
        show=False,                    # Don't auto-open
        graph_attr=graph_attr
    ):
        
        # Main VPC container
        with Cluster("AWS Region (us-east-1) - VPC"):
            
            # ===== HEAD NODE CLUSTER =====
            with Cluster("Head Node (EC2)"):
                # Core components
                slurm_controller = Compute("SLURM\nController\n(slurmctld)")
                job_plugin = Lambda("Job Submit\nPlugin\n(Lua)")
                prediction_api = SagemakerModel("Prediction API\n(ML Engine)")
                dashboard = Cloudwatch("Dashboard\n(Web UI)")
                metrics_db = RDS("Metrics DB\n(SQLite/RDS)")
                
                # Internal connections
                job_plugin >> Edge(label="query") >> prediction_api
                job_plugin >> Edge(label="submit") >> slurm_controller
                prediction_api >> Edge(label="history") >> metrics_db
            
            # ===== COMPUTE NODES CLUSTER =====
            with Cluster("Compute Nodes (Auto Scaling Group)"):
                compute_1 = EC2("Compute-1\nslurmd\nMonitor\n(c8/r8/m8)")
                compute_2 = EC2("Compute-2\nslurmd\nMonitor\n(c8/r8/m8)")
                compute_n = EC2("Compute-N\nslurmd\nMonitor\n(c8/r8/m8)")
                compute_nodes = [compute_1, compute_2, compute_n]
            
            # ===== SHARED STORAGE =====
            with Cluster("Shared Storage (Choose One)"):
                efs = EFS("Amazon EFS\n(General NFS)")
                fsx_lustre = FsxForLustre("FSx Lustre\n(HPC Optimized)")
                fsx_ontap = FSx("FSx ONTAP\n(Enterprise)")
                storage_options = [efs, fsx_lustre, fsx_ontap]
            
            # ===== AWS SERVICES =====
            with Cluster("AWS Services"):
                s3 = S3("S3\n(Backups)")
                rds_prod = RDS("RDS\n(Production DB)")
                cloudwatch = Cloudwatch("CloudWatch\n(Monitoring)")
                iam = IAM("IAM\n(Security)")
            
            # ===== DATA FLOWS =====
            
            # 1. Job dispatch (blue)
            slurm_controller >> Edge(label="dispatch", color="blue") >> compute_nodes
            
            # 2. Storage access (dashed gray)
            for node in compute_nodes:
                node >> Edge(style="dashed", color="gray") >> storage_options
            slurm_controller >> Edge(style="dashed", color="gray") >> storage_options
            
            # 3. Metrics feedback loop (green)
            for node in compute_nodes:
                node >> Edge(label="metrics", color="green") >> metrics_db
            
            # 4. Monitoring (dotted orange)
            for node in compute_nodes:
                node >> Edge(style="dotted", color="orange") >> cloudwatch
            slurm_controller >> Edge(style="dotted", color="orange") >> cloudwatch
            
            # 5. Backup to S3 (dotted purple)
            for node in compute_nodes:
                node >> Edge(style="dotted", color="purple") >> s3
            
            # 6. Database scaling option (dashed)
            metrics_db >> Edge(label="scale", style="dashed") >> rds_prod
    
    print("✓ Diagram generated successfully!")
    print("✓ Output: hpc-architecture.png")
    print("\nTo customize:")
    print("  - Change 'direction' parameter: TB, LR, BT, RL")
    print("  - Change 'filename' parameter for different output name")
    print("  - Modify edge colors, styles, and labels")
    print("  - Add/remove AWS services as needed")


def generate_simple_example():
    """
    Simple example: 3-tier web application
    Uncomment the function call below to generate this too
    """
    with Diagram("Simple 3-Tier Web App", filename="simple-3tier", show=False):
        from diagrams.aws.network import ELB
        
        lb = ELB("Load Balancer")
        
        with Cluster("Web Tier"):
            web = [EC2("web1"), EC2("web2"), EC2("web3")]
        
        with Cluster("Database"):
            db = RDS("PostgreSQL")
        
        lb >> web >> db
    
    print("✓ Simple example generated: simple-3tier.png")


if __name__ == "__main__":
    print("=" * 60)
    print("AWS Architecture Diagram Generator")
    print("=" * 60)
    print()
    
    # Generate main HPC architecture
    generate_hpc_architecture()
    
    # Uncomment to also generate simple example:
    # print()
    # generate_simple_example()
    
    print()
    print("=" * 60)
    print("Done! Check the current directory for PNG files.")
    print("=" * 60)
