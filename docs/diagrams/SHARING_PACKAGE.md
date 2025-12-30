# AWS Architecture Diagram Generation - Sharing Package

This package contains everything needed to generate AWS architecture diagrams using Python.

## Quick Start

```bash
# 1. Install dependencies
pip install diagrams graphviz

# 2. Run the generator
python generate_architecture_diagram.py

# 3. Find your diagram
# Output: hpc-architecture.png
```

## What's Included

1. **Python Script**: `generate_architecture_diagram.py` - Main diagram generator
2. **Requirements**: Dependencies needed
3. **Instructions**: How to customize and regenerate
4. **Examples**: Sample code for different diagram types

## Prerequisites

### System Requirements
- Python 3.8+
- GraphViz (system dependency)

### Install GraphViz

**macOS:**
```bash
brew install graphviz
```

**Ubuntu/Debian:**
```bash
sudo apt-get install graphviz
```

**Windows:**
Download from: https://graphviz.org/download/

### Install Python Dependencies

```bash
pip install diagrams
```

## The Generator Script

Save this as `generate_architecture_diagram.py`:

```python
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
        filename="hpc-architecture",
        direction="TB",
        show=False,
        graph_attr=graph_attr
    ):
        
        with Cluster("AWS Region (us-east-1) - VPC"):
            
            # Head Node Cluster
            with Cluster("Head Node (EC2)"):
                slurm_controller = Compute("SLURM\\nController\\n(slurmctld)")
                job_plugin = Lambda("Job Submit\\nPlugin\\n(Lua)")
                prediction_api = SagemakerModel("Prediction API\\n(ML Engine)")
                dashboard = Cloudwatch("Dashboard\\n(Web UI)")
                metrics_db = RDS("Metrics DB\\n(SQLite/RDS)")
                
                # Connections within head node
                job_plugin >> Edge(label="query") >> prediction_api
                job_plugin >> Edge(label="submit") >> slurm_controller
                prediction_api >> Edge(label="history") >> metrics_db
            
            # Compute Nodes Cluster
            with Cluster("Compute Nodes (Auto Scaling Group)"):
                compute_1 = EC2("Compute-1\\nslurmd\\nMonitor\\n(c8/r8/m8)")
                compute_2 = EC2("Compute-2\\nslurmd\\nMonitor\\n(c8/r8/m8)")
                compute_n = EC2("Compute-N\\nslurmd\\nMonitor\\n(c8/r8/m8)")
                compute_nodes = [compute_1, compute_2, compute_n]
            
            # Shared Storage
            with Cluster("Shared Storage (Choose One)"):
                efs = EFS("Amazon EFS\\n(General NFS)")
                fsx_lustre = FsxForLustre("FSx Lustre\\n(HPC Optimized)")
                fsx_ontap = FSx("FSx ONTAP\\n(Enterprise)")
                storage_options = [efs, fsx_lustre, fsx_ontap]
            
            # AWS Services
            with Cluster("AWS Services"):
                s3 = S3("S3\\n(Backups)")
                rds_prod = RDS("RDS\\n(Production DB)")
                cloudwatch = Cloudwatch("CloudWatch\\n(Monitoring)")
                iam = IAM("IAM\\n(Security)")
            
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
    
    print("✓ Diagram generated: hpc-architecture.png")

if __name__ == "__main__":
    generate_hpc_architecture()
```

## Running the Script

```bash
# Make executable (optional)
chmod +x generate_architecture_diagram.py

# Run it
python generate_architecture_diagram.py

# Output will be: hpc-architecture.png
```

## Customization Guide

### Change Output Format

```python
# In the Diagram() call, add:
outformat="svg"  # For vector graphics
outformat="pdf"  # For PDF
outformat="png"  # For PNG (default)
```

### Change Layout Direction

```python
direction="TB"  # Top to Bottom (default)
direction="LR"  # Left to Right
direction="BT"  # Bottom to Top
direction="RL"  # Right to Left
```

### Change Colors

```python
# Edge colors
Edge(color="blue")      # Blue
Edge(color="#FF0000")   # Red (hex)
Edge(color="green")     # Green

# Edge styles
Edge(style="solid")     # Solid line
Edge(style="dashed")    # Dashed line
Edge(style="dotted")    # Dotted line
Edge(style="bold")      # Bold line
```

### Add/Remove Components

```python
# Add a new AWS service
from diagrams.aws.network import ELB

# In your diagram:
load_balancer = ELB("Load\\nBalancer")

# Connect it
slurm_controller >> load_balancer >> compute_nodes
```

### Change Node Labels

```python
# Use \\n for line breaks in labels
node = EC2("Line 1\\nLine 2\\nLine 3")
```

## Available AWS Icons

The `diagrams` library includes official AWS service icons. Here are the most common:

### Compute
```python
from diagrams.aws.compute import (
    EC2, ECS, EKS, Lambda, Batch, 
    ElasticBeanstalk, Fargate
)
```

### Storage
```python
from diagrams.aws.storage import (
    S3, EBS, EFS, FSx, FsxForLustre,
    Glacier, StorageGateway
)
```

### Database
```python
from diagrams.aws.database import (
    RDS, DynamoDB, Redshift, ElastiCache,
    Neptune, DocumentDB
)
```

### Networking
```python
from diagrams.aws.network import (
    VPC, ELB, ALB, NLB, CloudFront,
    Route53, APIGateway, DirectConnect
)
```

### Management
```python
from diagrams.aws.management import (
    Cloudwatch, CloudFormation, SystemsManager,
    Config, Organizations
)
```

### ML/AI
```python
from diagrams.aws.ml import (
    Sagemaker, SagemakerModel, Comprehend,
    Rekognition, Textract
)
```

## Example: Simple 3-Tier Architecture

```python
from diagrams import Diagram, Cluster
from diagrams.aws.compute import EC2
from diagrams.aws.database import RDS
from diagrams.aws.network import ELB

with Diagram("Simple 3-Tier", show=False):
    lb = ELB("Load Balancer")
    
    with Cluster("Web Tier"):
        web = [EC2("web1"), EC2("web2")]
    
    with Cluster("Database"):
        db = RDS("MySQL")
    
    lb >> web >> db
```

## Troubleshooting

### Error: "GraphViz not found"
**Solution**: Install GraphViz system package
```bash
# macOS
brew install graphviz

# Ubuntu
sudo apt-get install graphviz
```

### Error: "Module 'diagrams' not found"
**Solution**: Install Python package
```bash
pip install diagrams
```

### Diagram looks cluttered
**Solution**: Adjust spacing
```python
graph_attr = {
    "nodesep": "1.0",  # Space between nodes
    "ranksep": "1.0",  # Space between ranks
    "pad": "0.5"       # Padding around diagram
}
```

### Text is too small
**Solution**: Increase font size
```python
graph_attr = {
    "fontsize": "16"  # Larger font
}

node_attr = {
    "fontsize": "14"  # Node font size
}
```

## Advanced: Multiple Diagrams

```python
# Generate multiple diagrams in one script
def generate_architecture():
    # ... architecture diagram code ...
    pass

def generate_dataflow():
    # ... dataflow diagram code ...
    pass

if __name__ == "__main__":
    generate_architecture()
    generate_dataflow()
    print("✓ All diagrams generated")
```

## Resources

- **Diagrams Documentation**: https://diagrams.mingrammer.com/
- **GraphViz Documentation**: https://graphviz.org/documentation/
- **AWS Architecture Icons**: https://aws.amazon.com/architecture/icons/
- **Example Gallery**: https://diagrams.mingrammer.com/docs/getting-started/examples

## Support

For issues or questions:
1. Check the diagrams documentation
2. Verify GraphViz is installed: `dot -V`
3. Verify Python package: `pip show diagrams`

## License

The `diagrams` library is MIT licensed. AWS service icons are provided by AWS.
