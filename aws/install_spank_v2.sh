#!/bin/bash
# SPANK Dynamic Allocation Plugin - Complete Installation v2
# Fixed: Added stdint.h and corrected SLURM constants

set -e

echo "════════════════════════════════════════════════════════════"
echo "  SPANK Dynamic Allocation Plugin - Installation v2"
echo "════════════════════════════════════════════════════════════"
echo ""

if [ "$EUID" -eq 0 ]; then 
    echo "Please run as ec2-user (not root)"
    exit 1
fi

echo "Step 1: Installing build tools..."
sudo yum install -y gcc 2>/dev/null || echo "gcc already installed"
echo "✓ Build tools ready"
echo ""

WORK_DIR="$HOME/spank_install_$$"
mkdir -p $WORK_DIR
cd $WORK_DIR

echo "Step 2: Creating SPANK plugin source..."
echo "────────────────────────────────────────────────────────────"

cat > spank_dynamic_alloc.c << 'EOFCODE'
/*
 * spank_dynamic_alloc.c - Dynamic memory allocation SPANK plugin
 */

#include <slurm/spank.h>
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <sys/resource.h>

SPANK_PLUGIN(spank_dynamic_alloc, 1);

static int gates_option = 0;

static struct spank_option spank_opts[] = {
    {
        "gates",
        "N",
        "Number of gates in design",
        1,
        0,
        NULL
    },
    SPANK_OPTIONS_TABLE_END
};

static int gates_opt_callback(int val, const char *optarg, int remote) {
    if (optarg) {
        gates_option = atoi(optarg);
        slurm_info("SPANK Dynamic: --gates=%d detected", gates_option);
    }
    return 0;
}

static size_t calculate_memory_mb(int gates) {
    size_t base_mb = 2000;
    size_t calculated_mb = base_mb + (gates * 0.08);
    size_t buffer_mb = calculated_mb * 0.2;
    size_t total_mb = calculated_mb + buffer_mb;
    
    slurm_info("SPANK Dynamic: Calculated %zu MB (%.1f GB) for %d gates", 
               total_mb, total_mb / 1024.0, gates);
    
    return total_mb;
}

static size_t get_slurm_mem_limit_mb(spank_t sp) {
    uint64_t mem_limit = 0;
    
    if (spank_get_item(sp, S_JOB_ALLOC_MEM, &mem_limit) == ESPANK_SUCCESS) {
        return (size_t)mem_limit;
    }
    
    char *mem_env = getenv("SLURM_MEM_PER_NODE");
    if (mem_env) {
        return (size_t)atol(mem_env);
    }
    
    return 0;
}

static int set_memory_limit(size_t limit_mb) {
    struct rlimit rlim;
    size_t limit_bytes = limit_mb * 1024 * 1024;
    
    rlim.rlim_cur = limit_bytes;
    rlim.rlim_max = limit_bytes;
    
    if (setrlimit(RLIMIT_AS, &rlim) != 0) {
        slurm_error("SPANK Dynamic: Failed to set memory limit");
        return -1;
    }
    
    slurm_info("SPANK Dynamic: Memory limit set to %zu MB", limit_mb);
    return 0;
}

int slurm_spank_init(spank_t sp, int ac, char **av) {
    spank_option_register(sp, &spank_opts[0]);
    
    if (spank_opts[0].cb == NULL) {
        spank_opts[0].cb = (spank_opt_cb_f)gates_opt_callback;
    }
    
    slurm_info("SPANK Dynamic: Plugin initialized");
    return ESPANK_SUCCESS;
}

int slurm_spank_task_init_privileged(spank_t sp, int ac, char **av) {
    uint32_t jobid = 0;
    size_t current_limit_mb, required_mb;
    
    spank_get_item(sp, S_JOB_ID, &jobid);
    
    if (gates_option == 0) {
        char *gates_env = getenv("DESIGN_GATES");
        if (gates_env) {
            gates_option = atoi(gates_env);
        } else {
            return ESPANK_SUCCESS;
        }
    }
    
    current_limit_mb = get_slurm_mem_limit_mb(sp);
    slurm_info("SPANK Dynamic: Job %u - Current allocation: %zu MB (%.1f GB)",
               jobid, current_limit_mb, current_limit_mb / 1024.0);
    
    required_mb = calculate_memory_mb(gates_option);
    
    if (required_mb > current_limit_mb) {
        size_t shortfall_mb = required_mb - current_limit_mb;
        slurm_info("SPANK Dynamic: Insufficient! Need %zu MB, have %zu MB (shortfall: %zu MB)",
                   required_mb, current_limit_mb, shortfall_mb);
        slurm_info("SPANK Dynamic: Adjusting memory limit...");
        
        if (set_memory_limit(required_mb) == 0) {
            slurm_info("SPANK Dynamic: ✓ Adjusted to %zu MB (%.1f GB)",
                       required_mb, required_mb / 1024.0);
        } else {
            slurm_error("SPANK Dynamic: ✗ Failed to adjust");
            return -1;
        }
    } else {
        slurm_info("SPANK Dynamic: ✓ Allocation sufficient (%zu MB)", current_limit_mb);
    }
    
    return ESPANK_SUCCESS;
}

int slurm_spank_task_post_fork(spank_t sp, int ac, char **av) {
    if (gates_option > 0) {
        slurm_info("SPANK Dynamic: Task starting with %d gates", gates_option);
    }
    return ESPANK_SUCCESS;
}
EOFCODE

echo "✓ Source code created"
echo ""

echo "Step 3: Compiling..."
echo "────────────────────────────────────────────────────────────"

gcc -shared -fPIC \
    -I/opt/slurm/include \
    -o spank_dynamic_alloc.so \
    spank_dynamic_alloc.c \
    -lpthread

if [ $? -ne 0 ]; then
    echo "✗ Compilation failed"
    exit 1
fi

echo "✓ Compilation successful"
echo ""

echo "Step 4: Installing..."
echo "────────────────────────────────────────────────────────────"

sudo mkdir -p /opt/slurm/lib/slurm
sudo cp spank_dynamic_alloc.so /opt/slurm/lib/slurm/
sudo chmod 755 /opt/slurm/lib/slurm/spank_dynamic_alloc.so

echo "✓ Installed to /opt/slurm/lib/slurm/spank_dynamic_alloc.so"
echo ""

echo "Step 5: Configuring..."
echo "────────────────────────────────────────────────────────────"

if [ -f /opt/slurm/etc/plugstack.conf ]; then
    sudo cp /opt/slurm/etc/plugstack.conf /opt/slurm/etc/plugstack.conf.backup.$(date +%s)
fi

sudo tee /opt/slurm/etc/plugstack.conf > /dev/null << 'EOFPLUG'
required /opt/slurm/lib/slurm/spank_dynamic_alloc.so
EOFPLUG

echo "✓ Configured /opt/slurm/etc/plugstack.conf"
echo ""

echo "Step 6: Restarting SLURM..."
echo "────────────────────────────────────────────────────────────"

sudo systemctl restart slurmctld
echo "✓ Restarted slurmctld"
sleep 3

echo ""
echo "Step 7: Verification..."
echo "────────────────────────────────────────────────────────────"

ls -lh /opt/slurm/lib/slurm/spank_dynamic_alloc.so

if sudo grep -q "SPANK Dynamic" /var/log/slurm/slurmctld.log 2>/dev/null; then
    echo "✓ Plugin loaded"
else
    echo "⚠  Check /var/log/slurm/slurmctld.log"
fi

echo ""
echo "════════════════════════════════════════════════════════════"
echo "  Installation Complete!"
echo "════════════════════════════════════════════════════════════"
echo ""
echo "Usage: sbatch --gates=100000 job.sh"
echo ""
echo "Test:"
echo "  sbatch --gates=100000 --wrap='echo test; sleep 10'"
echo "  sudo tail -f /var/log/slurm/slurmd.log | grep 'SPANK Dynamic'"
echo ""

cd $HOME
rm -rf $WORK_DIR
