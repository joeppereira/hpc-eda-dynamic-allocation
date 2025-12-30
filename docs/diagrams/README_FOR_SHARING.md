# AWS Architecture Diagram Generator - Quick Start

Share this with your colleague to generate AWS architecture diagrams.

## Files to Share

1. **generate_aws_diagram_standalone.py** - The main script (fully self-contained)
2. **SHARING_PACKAGE.md** - Complete documentation and examples
3. **This README** - Quick start guide

## 60-Second Setup

```bash
# 1. Install GraphViz (one-time setup)
brew install graphviz  # macOS
# OR
sudo apt-get install graphviz  # Ubuntu/Debian

# 2. Install Python package
pip install diagrams

# 3. Run the script
python generate_aws_diagram_standalone.py

# 4. Done! Check for hpc-architecture.png
```

## What You Get

The script generates a professional AWS architecture diagram showing:
- Head Node with SLURM scheduler, ML API, and dashboard
- Auto-scaling compute nodes (EC2)
- Shared storage options (EFS, FSx for Lustre, FSx ONTAP)
- AWS services (S3, RDS, CloudWatch, IAM)
- All data flows with color-coded connections

## Output Example

```
hpc-architecture.png  (232KB, high-resolution PNG)
```

## Customization Examples

### Change Layout Direction

```python
# In the Diagram() call:
direction="LR"  # Left to Right instead of Top to Bottom
```

### Change Output Format

```python
# In the Diagram() call:
outformat="svg"  # Vector graphics (scalable)
outformat="pdf"  # PDF format
```

### Add Your Own AWS Service

```python
from diagrams.aws.analytics import Kinesis

# In your diagram:
kinesis = Kinesis("Data Stream")
compute_nodes >> kinesis >> s3
```

### Change Colors

```python
# Blue edges
Edge(color="blue", label="data flow")

# Dashed lines
Edge(style="dashed", color="gray")

# Bold lines
Edge(style="bold", penwidth="3")
```

## Common AWS Services Available

```python
# Compute
from diagrams.aws.compute import EC2, Lambda, ECS, EKS, Batch

# Storage
from diagrams.aws.storage import S3, EFS, FSx, EBS, Glacier

# Database
from diagrams.aws.database import RDS, DynamoDB, Redshift, ElastiCache

# Networking
from diagrams.aws.network import VPC, ELB, ALB, CloudFront, Route53

# ML/AI
from diagrams.aws.ml import Sagemaker, Comprehend, Rekognition

# Analytics
from diagrams.aws.analytics import Kinesis, EMR, Athena, Glue

# Management
from diagrams.aws.management import Cloudwatch, CloudFormation, SystemsManager
```

## Troubleshooting

### "GraphViz not found"
```bash
# Install GraphViz first
brew install graphviz  # macOS
sudo apt-get install graphviz  # Linux
```

### "Module 'diagrams' not found"
```bash
pip install diagrams
```

### Diagram looks cluttered
```python
# Adjust spacing in graph_attr:
graph_attr = {
    "nodesep": "1.5",  # More space between nodes
    "ranksep": "2.0",  # More space between levels
}
```

## Full Documentation

See **SHARING_PACKAGE.md** for:
- Complete API reference
- Advanced examples
- All customization options
- Troubleshooting guide

## Resources

- **Diagrams Library**: https://diagrams.mingrammer.com/
- **Example Gallery**: https://diagrams.mingrammer.com/docs/getting-started/examples
- **AWS Icons**: https://aws.amazon.com/architecture/icons/

## Quick Examples

### Simple 3-Tier App

```python
from diagrams import Diagram, Cluster
from diagrams.aws.compute import EC2
from diagrams.aws.database import RDS
from diagrams.aws.network import ELB

with Diagram("3-Tier App", show=False):
    lb = ELB("LB")
    with Cluster("Web"):
        web = [EC2("web1"), EC2("web2")]
    db = RDS("DB")
    
    lb >> web >> db
```

### Microservices Architecture

```python
from diagrams import Diagram, Cluster
from diagrams.aws.compute import ECS, Lambda
from diagrams.aws.database import DynamoDB
from diagrams.aws.network import APIGateway

with Diagram("Microservices", show=False):
    api = APIGateway("API")
    
    with Cluster("Services"):
        svc1 = ECS("Service 1")
        svc2 = ECS("Service 2")
        func = Lambda("Function")
    
    db = DynamoDB("DB")
    
    api >> [svc1, svc2, func] >> db
```

## Support

Questions? Check:
1. SHARING_PACKAGE.md (comprehensive guide)
2. https://diagrams.mingrammer.com/docs/getting-started/installation
3. GraphViz installation: https://graphviz.org/download/

---

**That's it!** Run the script and you'll have a professional AWS architecture diagram in seconds.
