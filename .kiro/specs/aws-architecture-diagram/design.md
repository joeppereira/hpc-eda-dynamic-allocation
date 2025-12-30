# Design Document

## Overview

This design describes the implementation of an automated AWS architecture diagram generation system using Amazon Q CLI and Model Context Protocol (MCP). The system will convert the existing ASCII Figure 1 from the blog post into a professional, publication-ready AWS architecture diagram with official AWS icons and proper visual hierarchy.

## Architecture

### System Components

1. **Amazon Q CLI Setup**
   - AWS CLI authentication and configuration
   - Amazon Q CLI installation via npm or pip
   - MCP server configuration for architecture diagrams

2. **Architecture Parser**
   - Python script to extract components from Figure 1
   - Component categorization (compute, storage, networking, services)
   - Relationship mapping between components

3. **Diagram Generator**
   - Amazon Q CLI invocation with structured prompts
   - MCP integration for diagram generation
   - Output format handling (PNG, SVG, draw.io)

4. **Automation Script**
   - Bash script for end-to-end diagram generation
   - Configuration file for architecture description
   - Validation and error handling

## Components and Interfaces

### 1. Setup Script (`scripts/setup_amazon_q_diagram.sh`)

```bash
#!/bin/bash
# Install Amazon Q CLI
# Configure MCP for architecture diagrams
# Verify authentication and connectivity
```

**Inputs:**
- AWS credentials (from environment or ~/.aws/credentials)
- MCP configuration file path

**Outputs:**
- Installation status
- Configuration validation results

### 2. Architecture Description (`docs/architecture_description.yaml`)

```yaml
architecture:
  name: "ML-Driven HPC Resource Optimization"
  region: "us-east-1"
  
  vpc:
    cidr: "10.0.0.0/16"
    
  components:
    head_node:
      type: "EC2"
      services:
        - "SLURM Controller"
        - "Job Submit Plugin"
        - "Prediction API"
        - "Dashboard"
        - "Metrics Database"
    
    compute_nodes:
      type: "Auto Scaling Group"
      instance_types: ["c8", "r8", "m8"]
      services:
        - "slurmd"
        - "Resource Monitor"
        - "Workload Execution"
    
    storage:
      options:
        - type: "Amazon EFS"
        - type: "FSx for Lustre"
        - type: "FSx for NetApp ONTAP"
    
    aws_services:
      - "Amazon S3"
      - "Amazon RDS"
      - "Amazon CloudWatch"
      - "AWS IAM"
  
  connections:
    - from: "Users"
      to: "Head Node"
      protocol: "SSH/HTTPS"
    - from: "Head Node"
      to: "Compute Nodes"
      protocol: "SLURM"
    - from: "All Nodes"
      to: "Shared Storage"
      protocol: "NFS/Lustre"
```

### 3. Diagram Generator Script (`scripts/generate_aws_diagram.py`)

```python
import subprocess
import yaml
import json

def load_architecture_description(yaml_file):
    """Load architecture from YAML configuration"""
    pass

def create_amazon_q_prompt(architecture):
    """Convert architecture description to Amazon Q CLI prompt"""
    pass

def generate_diagram(prompt, output_format):
    """Invoke Amazon Q CLI to generate diagram"""
    pass

def validate_output(output_file):
    """Verify diagram was generated successfully"""
    pass
```

**Inputs:**
- Architecture description YAML file
- Output format specification (PNG, SVG, drawio)
- Output directory path

**Outputs:**
- Generated diagram files
- Generation log
- Validation report

### 4. Automation Script (`scripts/create_architecture_diagram.sh`)

```bash
#!/bin/bash
# Main automation script
# 1. Validate prerequisites
# 2. Load architecture description
# 3. Generate diagram using Amazon Q CLI
# 4. Export in multiple formats
# 5. Validate outputs
```

## Data Models

### Architecture Description Schema

```yaml
architecture:
  name: string
  region: string
  vpc:
    cidr: string
    subnets: array
  components:
    - name: string
      type: string (EC2, ASG, EFS, etc.)
      services: array
      properties: object
  connections:
    - from: string
      to: string
      protocol: string
      bidirectional: boolean
```

### Diagram Configuration

```json
{
  "output_formats": ["png", "svg", "drawio"],
  "resolution": {
    "width": 1920,
    "height": 1080
  },
  "style": {
    "theme": "aws-official",
    "layout": "hierarchical",
    "direction": "top-to-bottom"
  }
}
```

## Correctness Properties

*A property is a characteristic or behavior that should hold true across all valid executions of a system—essentially, a formal statement about what the system should do. Properties serve as the bridge between human-readable specifications and machine-verifiable correctness guarantees.*

### Property 1: Complete Component Representation

*For any* architecture description containing N components, the generated diagram should visually represent all N components with correct AWS service icons.

**Validates: Requirements 2.1, 2.2, 2.3, 5.1, 5.2**

### Property 2: Connection Preservation

*For any* set of connections defined in the architecture description, all connections should be visible in the generated diagram with appropriate directional arrows.

**Validates: Requirements 2.4, 5.3**

### Property 3: Output Format Completeness

*For any* requested output format (PNG, SVG, drawio), the system should generate a valid file in that format that can be opened by standard tools.

**Validates: Requirements 6.1, 6.2, 6.3**

### Property 4: AWS Service Icon Accuracy

*For any* AWS service specified in the architecture description, the generated diagram should use the official AWS icon for that service.

**Validates: Requirements 4.2**

### Property 5: Idempotent Generation

*For any* architecture description, running the generation script multiple times should produce visually equivalent diagrams (same components, same connections, same layout).

**Validates: Requirements 7.2, 7.4**

## Error Handling

### Amazon Q CLI Errors

- **Authentication Failure**: Check AWS credentials and re-authenticate
- **MCP Connection Error**: Verify MCP server is running and configured
- **Rate Limiting**: Implement exponential backoff and retry logic
- **Invalid Prompt**: Validate architecture description before sending

### File System Errors

- **Missing Input File**: Validate architecture description file exists
- **Write Permission Denied**: Check output directory permissions
- **Disk Space**: Verify sufficient space for diagram files

### Validation Errors

- **Missing Components**: Report which components from Figure 1 are missing
- **Incorrect Connections**: List connections that don't match the original
- **Format Errors**: Specify which output formats failed to generate

## Testing Strategy

### Unit Tests

- Test architecture description YAML parsing
- Test Amazon Q CLI prompt generation
- Test output file validation
- Test error handling for each error type

### Integration Tests

- Test end-to-end diagram generation with sample architecture
- Test multiple output format generation
- Test diagram regeneration (idempotency)
- Test with different architecture configurations

### Manual Validation

- Visual comparison of generated diagram with Figure 1
- Verify all AWS services are correctly represented
- Check that connections and data flows are clear
- Confirm diagram is suitable for publication

### Property-Based Tests

Each correctness property should be tested with:
- Minimum 100 iterations per test
- Random architecture descriptions with varying complexity
- Different combinations of AWS services
- Various connection patterns

## Implementation Notes

### Amazon Q CLI Setup

According to the AWS blog post, the setup involves:

1. Install Amazon Q CLI:
```bash
npm install -g @aws/amazon-q-cli
# or
pip install amazon-q-cli
```

2. Configure MCP for architecture diagrams:
```bash
q configure mcp --server architecture-diagrams
```

3. Authenticate:
```bash
q auth login
```

### Diagram Generation Command

```bash
q diagram create \
  --description "$(cat docs/architecture_description.yaml)" \
  --output docs/diagrams/hpc-architecture \
  --format png,svg,drawio \
  --style aws-official
```

### Alternative: Direct MCP Integration

If Amazon Q CLI doesn't support diagram generation directly, we can use MCP tools:

```python
import mcp_client

client = mcp_client.MCPClient()
result = client.call_tool(
    "architecture-diagram",
    "generate",
    {
        "description": architecture_yaml,
        "format": "png",
        "style": "aws-official"
    }
)
```

## Deployment

### Prerequisites

- AWS CLI installed and configured
- Node.js or Python (for Amazon Q CLI)
- MCP server for architecture diagrams
- Write access to docs/diagrams/ directory

### Installation Steps

1. Run setup script: `./scripts/setup_amazon_q_diagram.sh`
2. Verify configuration: `q diagram --version`
3. Test with sample: `./scripts/create_architecture_diagram.sh --test`
4. Generate production diagram: `./scripts/create_architecture_diagram.sh`

### Output Structure

```
docs/diagrams/
├── hpc-architecture.png          # High-res PNG
├── hpc-architecture.svg          # Scalable vector
├── hpc-architecture.drawio       # Editable diagram
├── README.md                     # Usage instructions
└── generation.log                # Generation details
```

