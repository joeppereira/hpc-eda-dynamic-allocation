#!/bin/bash
# Check SLURM and system versions

echo "════════════════════════════════════════════════════════════"
echo "  Version Information"
echo "════════════════════════════════════════════════════════════"
echo ""

echo "SLURM Version:"
echo "────────────────────────────────────────────────────────────"
scontrol --version
slurmd -V 2>&1 | head -1
echo ""

echo "Operating System:"
echo "────────────────────────────────────────────────────────────"
cat /etc/os-release | grep -E "^NAME=|^VERSION="
uname -r
echo ""

echo "GCC Version:"
echo "────────────────────────────────────────────────────────────"
gcc --version | head -1
echo ""

echo "Python Version:"
echo "────────────────────────────────────────────────────────────"
python3 --version
echo ""

echo "AWS ParallelCluster Info:"
echo "────────────────────────────────────────────────────────────"
if [ -f /opt/parallelcluster/.bootstrapped ]; then
    echo "ParallelCluster detected"
    if command -v pcluster &> /dev/null; then
        pcluster version 2>&1 || echo "pcluster command not available"
    fi
    
    # Check for version file
    if [ -f /opt/parallelcluster/version ]; then
        echo "Version: $(cat /opt/parallelcluster/version)"
    fi
else
    echo "Not running on ParallelCluster (or version file not found)"
fi
echo ""

echo "SLURM Configuration:"
echo "────────────────────────────────────────────────────────────"
if [ -f /opt/slurm/etc/slurm.conf ]; then
    echo "SLURM config location: /opt/slurm/etc/slurm.conf"
    echo "Key settings:"
    grep -E "^ClusterName=|^SlurmctldHost=|^AccountingStorageType=|^JobAcctGatherType=" /opt/slurm/etc/slurm.conf | grep -v "^#"
else
    echo "slurm.conf not found"
fi
echo ""

echo "SPANK Plugin Info:"
echo "────────────────────────────────────────────────────────────"
if [ -f /opt/slurm/lib/slurm/spank_dynamic_alloc.so ]; then
    echo "Plugin file: /opt/slurm/lib/slurm/spank_dynamic_alloc.so"
    ls -lh /opt/slurm/lib/slurm/spank_dynamic_alloc.so
    echo ""
    echo "Compiled on: $(stat -c %y /opt/slurm/lib/slurm/spank_dynamic_alloc.so 2>/dev/null || stat -f %Sm /opt/slurm/lib/slurm/spank_dynamic_alloc.so)"
else
    echo "Plugin not found"
fi
echo ""

if [ -f /opt/slurm/etc/plugstack.conf ]; then
    echo "plugstack.conf:"
    cat /opt/slurm/etc/plugstack.conf
else
    echo "plugstack.conf not found"
fi
echo ""

echo "SLURM Cgroup Configuration:"
echo "────────────────────────────────────────────────────────────"
if [ -f /opt/slurm/etc/cgroup.conf ]; then
    echo "cgroup.conf exists:"
    cat /opt/slurm/etc/cgroup.conf | grep -v "^#" | grep -v "^$"
else
    echo "cgroup.conf not found (using defaults)"
fi
echo ""

echo "════════════════════════════════════════════════════════════"
echo "  Summary"
echo "════════════════════════════════════════════════════════════"
echo ""

SLURM_VERSION=$(scontrol --version | grep -oP '\d+\.\d+\.\d+')
echo "SLURM Version: $SLURM_VERSION"

# Check if version supports task_init_privileged
MAJOR=$(echo $SLURM_VERSION | cut -d. -f1)
MINOR=$(echo $SLURM_VERSION | cut -d. -f2)

if [ "$MAJOR" -ge 20 ]; then
    echo "✓ SLURM version should support task_init_privileged hook"
else
    echo "⚠  SLURM version may have limited SPANK support"
fi

echo ""
echo "Recommendations:"
echo "  - SLURM 20.x+ recommended for full SPANK support"
echo "  - Check SPANK documentation for version $SLURM_VERSION"
echo "  - Consider cgroup memory controller instead of setrlimit()"
echo ""
