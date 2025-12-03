#!/bin/bash
# Check SPANK plugin logs across cluster

echo "════════════════════════════════════════════════════════════"
echo "  SPANK Plugin Log Checker"
echo "════════════════════════════════════════════════════════════"
echo ""

# Get job ID from argument or use latest
if [ -n "$1" ]; then
    JOBID=$1
else
    JOBID=$(squeue -h -u $USER -o "%i" | head -1)
    if [ -z "$JOBID" ]; then
        echo "No running jobs found. Checking recent jobs..."
        JOBID=$(sacct -u $USER -n -X -o jobid | tail -1 | tr -d ' ')
    fi
fi

echo "Checking logs for Job ID: $JOBID"
echo ""

# Get node where job ran
NODE=$(scontrol show job $JOBID 2>/dev/null | grep -oP 'NodeList=\K[^ ]+')

if [ -z "$NODE" ]; then
    echo "Could not find node for job $JOBID"
    echo ""
    echo "Recent jobs:"
    sacct -u $USER -X -o jobid,nodelist,state -n | tail -5
    exit 1
fi

echo "Job ran on node: $NODE"
echo ""

# Check if we can access the node
if ping -c 1 -W 1 $NODE &>/dev/null; then
    echo "Fetching SPANK logs from $NODE..."
    echo "────────────────────────────────────────────────────────────"
    
    # Try to get logs via SSH
    ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 $NODE \
        "sudo grep 'SPANK Dynamic' /var/log/slurm/slurmd.log 2>/dev/null | grep 'Job $JOBID'" 2>/dev/null
    
    if [ $? -eq 0 ]; then
        echo ""
        echo "✓ SPANK logs retrieved"
    else
        echo "Could not retrieve logs via SSH"
        echo ""
        echo "Manual check:"
        echo "  ssh $NODE"
        echo "  sudo grep 'SPANK Dynamic' /var/log/slurm/slurmd.log | grep 'Job $JOBID'"
    fi
else
    echo "Cannot reach node $NODE"
    echo ""
    echo "To check manually:"
    echo "  1. SSH to compute node: ssh $NODE"
    echo "  2. Check logs: sudo grep 'SPANK Dynamic' /var/log/slurm/slurmd.log"
fi

echo ""
echo "════════════════════════════════════════════════════════════"
echo ""
echo "All SPANK activity on head node:"
echo "────────────────────────────────────────────────────────────"

# Check head node logs
for logfile in /var/log/slurm/slurmctld.log /opt/slurm/var/log/slurmctld.log /var/log/slurmctld.log; do
    if [ -f "$logfile" ]; then
        sudo grep "SPANK Dynamic" "$logfile" 2>/dev/null | tail -10
        break
    fi
done

echo ""
