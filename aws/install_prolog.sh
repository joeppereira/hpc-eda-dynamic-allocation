#!/bin/bash
# Install SLURM prolog script for dynamic memory allocation

set -e

echo "════════════════════════════════════════════════════════════"
echo "  SLURM Prolog Script Installation"
echo "════════════════════════════════════════════════════════════"
echo ""

# Create prolog directory
echo "Creating prolog directory..."
sudo mkdir -p /opt/slurm/etc/scripts/prolog.d
sudo chmod 755 /opt/slurm/etc/scripts/prolog.d

# Copy prolog script
echo "Installing prolog script..."
sudo cp slurm/prolog_dynamic_alloc.sh /opt/slurm/etc/scripts/prolog.d/
sudo chmod 755 /opt/slurm/etc/scripts/prolog.d/prolog_dynamic_alloc.sh

echo "✓ Prolog script installed"
echo ""

# Check current slurm.conf for Prolog setting
echo "Checking slurm.conf..."
if grep -q "^Prolog=" /opt/slurm/etc/slurm.conf; then
    echo "✓ Prolog already configured in slurm.conf"
    grep "^Prolog=" /opt/slurm/etc/slurm.conf
else
    echo "⚠  Prolog not configured in slurm.conf"
    echo "   Current setting:"
    grep "Prolog=" /opt/slurm/etc/slurm.conf || echo "   (not set)"
fi

echo ""
echo "════════════════════════════════════════════════════════════"
echo "  Installation Complete"
echo "════════════════════════════════════════════════════════════"
echo ""
echo "The prolog script is installed at:"
echo "  /opt/slurm/etc/scripts/prolog.d/prolog_dynamic_alloc.sh"
echo ""
echo "It will run automatically for all jobs (configured in slurm.conf)"
echo ""
echo "Test with:"
echo "  sbatch --export=ALL,DESIGN_GATES=100000 --mem=4096M \\"
echo "    --wrap='echo test; sleep 5'"
echo ""
echo "Check logs:"
echo "  # On compute node"
echo "  journalctl -t prolog_dynamic"
echo "  # Or"
echo "  grep prolog_dynamic /var/log/messages"
echo ""
