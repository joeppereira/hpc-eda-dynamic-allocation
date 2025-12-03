#!/bin/bash
# Python environment setup for SLURM jobs
# Source this in all job scripts to ensure correct Python path

# Add local Python packages to path
export PYTHONPATH=/usr/local/lib64/python3.7/site-packages:$PYTHONPATH

# Verify psutil is available
if ! python3 -c "import psutil" 2>/dev/null; then
    echo "WARNING: psutil not found, attempting to add to path..."
    # Try common locations
    for path in /usr/local/lib64/python3.*/site-packages /usr/local/lib/python3.*/site-packages; do
        if [ -d "$path" ] && [ -f "$path/psutil/__init__.py" ]; then
            export PYTHONPATH=$path:$PYTHONPATH
            echo "Added $path to PYTHONPATH"
            break
        fi
    done
fi

# Verify it works
if python3 -c "import psutil" 2>/dev/null; then
    echo "✓ Python environment ready (psutil available)"
else
    echo "✗ ERROR: psutil still not available"
    echo "  Install with: pip3 install --user psutil"
    exit 1
fi
