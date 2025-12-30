# Share This Package With Your Colleague

## What to Send

Send these 3 files from the `docs/diagrams/` directory:

1. **generate_aws_diagram_standalone.py** - The complete working script
2. **README_FOR_SHARING.md** - Quick start guide (5 minutes to first diagram)
3. **SHARING_PACKAGE.md** - Full documentation with examples

## Quick Instructions for Your Colleague

### Step 1: Install Prerequisites (One-Time)

```bash
# Install GraphViz (system dependency)
brew install graphviz  # macOS
# OR
sudo apt-get install graphviz  # Ubuntu/Debian

# Install Python library
pip install diagrams
```

### Step 2: Run the Script

```bash
python generate_aws_diagram_standalone.py
```

### Step 3: Get the Diagram

Output file: `hpc-architecture.png`

That's it! 🎉

## What They'll Get

A professional AWS architecture diagram showing:
- ✓ Head Node with SLURM, ML API, Dashboard, Metrics DB
- ✓ Auto-scaling compute nodes (c8/r8/m8 instances)
- ✓ Shared storage options (EFS, FSx Lustre, FSx ONTAP)
- ✓ AWS services (S3, RDS, CloudWatch, IAM)
- ✓ Color-coded data flows
- ✓ Professional layout with official AWS icons

## Customization

The script is fully customizable:
- Change layout direction (TB, LR, BT, RL)
- Modify colors and styles
- Add/remove AWS services
- Change output format (PNG, SVG, PDF)
- Adjust spacing and fonts

All examples are in **SHARING_PACKAGE.md**

## Alternative: Email Instructions

If you prefer to send instructions via email:

---

**Subject:** AWS Architecture Diagram Generator

Hi [Colleague],

I'm sharing a Python script that generates professional AWS architecture diagrams. Here's how to use it:

**Setup (one-time):**
```bash
brew install graphviz  # or apt-get on Linux
pip install diagrams
```

**Run:**
```bash
python generate_aws_diagram_standalone.py
```

**Output:** hpc-architecture.png

The script is fully customizable - see the comments in the code for examples.

Attached files:
- generate_aws_diagram_standalone.py (the script)
- README_FOR_SHARING.md (quick start)
- SHARING_PACKAGE.md (full docs)

Let me know if you have questions!

---

## File Locations

All files are in: `/Users/spereirj/dynamic_allocation/docs/diagrams/`

```
docs/diagrams/
├── generate_aws_diagram_standalone.py  ← Main script
├── README_FOR_SHARING.md               ← Quick start
├── SHARING_PACKAGE.md                  ← Full documentation
└── SHARE_WITH_COLLEAGUE.md             ← This file
```

## What's Already Generated

You also have these ready-to-use diagrams:
- `hpc-architecture.png` - Full AWS architecture
- `dataflow-simple.png` - 5-stage flow diagram
- `dataflow-simple.docx` - Editable Word version
- `container-execution.docx` - Container flow (Word)

## Support Resources

If your colleague needs help:
1. **Quick Start**: README_FOR_SHARING.md
2. **Full Docs**: SHARING_PACKAGE.md
3. **Library Docs**: https://diagrams.mingrammer.com/
4. **Examples**: https://diagrams.mingrammer.com/docs/getting-started/examples

## Testing Before Sharing

To verify everything works:

```bash
cd docs/diagrams/
python generate_aws_diagram_standalone.py
# Should output: hpc-architecture.png
```

## Package Size

Total size: ~15KB (3 text files)
- Script: ~5KB
- README: ~5KB  
- Full docs: ~5KB

Easy to email or share via Slack/Teams!
