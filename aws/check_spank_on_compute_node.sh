#!/bin/bash
# Run this script directly on a compute node (after SSH)
# Usage: ssh compute-node-name, then run this script

echo "════════════════════════════════════════════════════════════"
echo "  SPANK Plugin Check - Direct on Compute Node"
echo "════════════════════════════════════════════════════════════"
echo ""
echo "Node: $(hostname)"
echo "Date: $(date)"
echo ""

echo "1. SPANK Plugin File"
echo "────────────────────────────────────────────────────────────"
if [ -f /opt/slurm/lib/slurm/spank_dynamic_alloc.so ]; then
    echo "✓ Plugin file exists"
    ls -lh /opt/slurm/lib/slurm/spank_dynamic_alloc.so
    echo ""
    echo "File type:"
    file /opt/slurm/lib/slurm/spank_dynamic_alloc.so
    echo ""
    echo "Dependencies:"
    ldd /opt/slurm/lib/slurm/spank_dynamic_alloc.so 2>&1 | head -10
else
    echo "✗ Plugin file NOT found"
    echo ""
    echo "Searching for any SPANK plugins:"
    find /opt/slurm -name "*.so" 2>/dev/null
fi
echo ""

echo "2. SPANK Configuration"
echo "────────────────────────────────────────────────────────────"
if [ -f /opt/slurm/etc/plugstack.conf ]; then
    echo "✓ plugstack.conf exists"
    echo "Content:"
    cat /opt/slurm/etc/plugstack.conf
else
    echo "✗ plugstack.conf NOT found"
fi
echo ""

echo "3. NFS Mount Status"
echo "────────────────────────────────────────────────────────────"
echo "/opt/slurm mount:"
df -h /opt/slurm 2>&1
echo ""
echo "All NFS mounts:"
mount | grep nfs
echo ""

echo "4. SLURM Version"
echo "────────────────────────────────────────────────────────────"
slurmd -V 2>&1
echo ""

echo "5. SLURM Configuration"
echo "────────────────────────────────────────────────────────────"
if [ -f /opt/slurm/etc/slurm.conf ]; then
    echo "SLURM config exists"
    echo "Relevant settings:"
    grep -E "SlurmdLogFile|PlugStackConfig" /opt/slurm/etc/slurm.conf | grep -v "^#"
else
    echo "slurm.conf not found"
fi
echo ""

echo "6. Slurmd Service Status"
echo "────────────────────────────────────────────────────────────"
systemctl status slurmd --no-pager -l | head -20
echo ""

echo "7. Recent Slurmd Logs (SPANK related)"
echo "────────────────────────────────────────────────────────────"
echo "Checking journald..."
journalctl -u slurmd --no-pager -n 100 2>/dev/null | grep -i spank || echo "No SPANK messages in journal"
echo ""

if [ -f /var/log/slurmd.log ]; then
    echo "Checking /var/log/slurmd.log..."
    tail -100 /var/log/slurmd.log | grep -i spank || echo "No SPANK messages in log file"
fi
echo ""

echo "8. SPANK Plugin Load Errors"
echo "────────────────────────────────────────────────────────────"
journalctl -u slurmd --no-pager 2>/dev/null | grep -i "spank.*error\|spank.*fail\|plugin.*error" | tail -10 || echo "No errors found"
echo ""

echo "9. Test Plugin Loading"
echo "────────────────────────────────────────────────────────────"
if [ -f /opt/slurm/lib/slurm/spank_dynamic_alloc.so ]; then
    echo "Checking if plugin can be loaded (symbols):"
    nm -D /opt/slurm/lib/slurm/spank_dynamic_alloc.so 2>&1 | grep -E "slurm_spank|plugin_name" | head -10
else
    echo "Plugin file not accessible"
fi
echo ""

echo "10. Environment Check"
echo "────────────────────────────────────────────────────────────"
echo "User: $(whoami)"
echo "Groups: $(groups)"
echo "LD_LIBRARY_PATH: ${LD_LIBRARY_PATH:-not set}"
echo "SLURM_CONF: ${SLURM_CONF:-not set}"
echo ""

echo "════════════════════════════════════════════════════════════"
echo "  Summary"
echo "════════════════════════════════════════════════════════════"
echo ""

# Quick summary
PLUGIN_OK=false
CONFIG_OK=false
LOADED_OK=false

if [ -f /opt/slurm/lib/slurm/spank_dynamic_alloc.so ]; then
    PLUGIN_OK=true
    echo "✓ Plugin file accessible"
else
    echo "✗ Plugin file NOT accessible"
fi

if [ -f /opt/slurm/etc/plugstack.conf ]; then
    CONFIG_OK=true
    echo "✓ Configuration file accessible"
else
    echo "✗ Configuration file NOT accessible"
fi

if journalctl -u slurmd --no-pager -n 100 2>/dev/null | grep -q "SPANK Dynamic.*initialized"; then
    LOADED_OK=true
    echo "✓ Plugin is loading (found initialization message)"
else
    echo "⚠  Plugin initialization not confirmed in recent logs"
fi

echo ""
if $PLUGIN_OK && $CONFIG_OK; then
    echo "Status: SPANK plugin should be working"
    if ! $LOADED_OK; then
        echo "Note: May need to wait for a job to run to see initialization"
    fi
else
    echo "Status: SPANK plugin setup incomplete"
    echo ""
    echo "Troubleshooting:"
    [ ! $PLUGIN_OK ] && echo "  - Ensure /opt/slurm is NFS-mounted from head node"
    [ ! $CONFIG_OK ] && echo "  - Ensure plugstack.conf is in shared location"
fi
echo ""
