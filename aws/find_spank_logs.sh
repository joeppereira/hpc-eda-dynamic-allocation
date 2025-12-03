#!/bin/bash
# Find SPANK plugin logs wherever they are

echo "════════════════════════════════════════════════════════════"
echo "  SPANK Log Finder"
echo "════════════════════════════════════════════════════════════"
echo ""

echo "Step 1: Checking SLURM configuration..."
echo "────────────────────────────────────────────────────────────"
if [ -f /opt/slurm/etc/slurm.conf ]; then
    echo "Log file locations from slurm.conf:"
    grep -E "SlurmctldLogFile|SlurmdLogFile" /opt/slurm/etc/slurm.conf | grep -v "^#"
    echo ""
fi

echo "Step 2: Searching for SLURM log files..."
echo "────────────────────────────────────────────────────────────"
echo "Finding all SLURM log files..."
LOGFILES=$(sudo find /var /opt -name "*slurm*.log" 2>/dev/null)
if [ -n "$LOGFILES" ]; then
    echo "$LOGFILES"
else
    echo "No SLURM log files found"
fi
echo ""

echo "Step 3: Checking systemd journal (head node)..."
echo "────────────────────────────────────────────────────────────"
echo "Recent slurmctld logs with SPANK:"
sudo journalctl -u slurmctld --no-pager -n 100 2>/dev/null | grep -i "spank" | tail -10
if [ $? -ne 0 ]; then
    echo "No SPANK messages in slurmctld journal"
fi
echo ""

echo "Step 4: Checking for compute nodes..."
echo "────────────────────────────────────────────────────────────"
NODES=$(sinfo -h -o "%N" | head -1)
if [ -n "$NODES" ]; then
    echo "Compute nodes: $NODES"
    echo ""
    
    # Try to check first compute node
    FIRST_NODE=$(scontrol show hostname $NODES | head -1)
    echo "Attempting to check logs on: $FIRST_NODE"
    
    if ping -c 1 -W 2 $FIRST_NODE &>/dev/null; then
        echo "Node is reachable, checking for SPANK logs..."
        
        # Check via SSH
        ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 $FIRST_NODE \
            "sudo journalctl -u slurmd --no-pager -n 50 2>/dev/null | grep -i spank" 2>/dev/null
        
        if [ $? -eq 0 ]; then
            echo "✓ Found SPANK logs via journald on compute node"
        else
            echo "Checking file-based logs on compute node..."
            ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 $FIRST_NODE \
                "sudo find /var /opt -name '*slurm*.log' 2>/dev/null" 2>/dev/null
        fi
    else
        echo "Compute node not reachable (may not be running)"
    fi
else
    echo "No compute nodes found (cluster may be idle)"
fi
echo ""

echo "════════════════════════════════════════════════════════════"
echo "  Summary"
echo "════════════════════════════════════════════════════════════"
echo ""
echo "SPANK plugin logs location depends on your setup:"
echo ""
echo "Option 1: File-based logging"
echo "  Head node: /var/log/slurmctld.log or /opt/slurm/var/log/slurmctld.log"
echo "  Compute nodes: /var/log/slurmd.log"
echo ""
echo "Option 2: Systemd journal (AWS ParallelCluster default)"
echo "  Head node: sudo journalctl -u slurmctld | grep SPANK"
echo "  Compute nodes: sudo journalctl -u slurmd | grep SPANK"
echo ""
echo "To test SPANK plugin:"
echo "  1. Submit a job: sbatch --gates=100000 --wrap='sleep 10'"
echo "  2. Get job ID: squeue -u \$USER"
echo "  3. Check logs using commands above"
echo ""
