# AWS Architecture Diagrams

This directory contains generated AWS architecture diagrams for the ML-Driven HPC Resource Optimization System.

## Generated Diagrams

### hpc-architecture.png
**ML-Driven HPC Resource Optimization System Architecture**

This diagram illustrates the complete system architecture deployed on AWS ParallelCluster, showing:

- **Head Node**: SLURM Controller, Job Submit Plugin, Prediction API, Dashboard, Metrics Database
- **Compute Nodes**: Auto-scaling EC2 instances (c8/r8/m8) with slurmd, monitors, and workload execution
- **Shared Storage**: EFS, FSx for Lustre, or FSx for NetApp ONTAP options
- **AWS Services**: S3, RDS, CloudWatch, IAM
- **Data Flows**: Job submission, prediction, allocation, execution, and metrics feedback loop

**Source**: Based on Figure 1 from `docs/BLOG_POST_ARCHITECTURE_DIAGRAM.md`

## Regenerating Diagrams

To regenerate the architecture diagram:

```bash
# Activate virtual environment
source venv/bin/activate

# Run the generation script
python scripts/generate_architecture_diagram.py
```

The script will:
1. Use the Python `diagrams` library to create the diagram
2. Generate official AWS service icons
3. Save output to `docs/diagrams/hpc-architecture.png`

## Requirements

- Python 3.13+
- diagrams library (installed in venv)
- GraphViz (system dependency)

## Customization

To modify the diagram, edit `scripts/generate_architecture_diagram.py`:

- Add/remove components
- Change layout direction (TB, LR, BT, RL)
- Adjust edge labels and colors
- Modify cluster organization

## File Information

- **Format**: PNG
- **Size**: ~232KB
- **Generated**: December 26, 2024
- **Tool**: Python diagrams library v0.25.1
