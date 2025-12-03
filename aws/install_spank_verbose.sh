#!/bin/bash
# Install SPANK plugin with verbose logging to debug hook execution

set -e

echo "════════════════════════════════════════════════════════════"
echo "  SPANK Plugin - Verbose Debug Version"
echo "════════════════════════════════════════════════════════════"
echo ""

WORK_DIR="$HOME/spank_verbose_$$"
mkdir -p $WORK_DIR
cd $WORK_DIR

echo "Creating verbose SPANK plugin..."

cat > spank_dynamic_alloc_verbose.c << 'EOFCODE'
#include <slurm/spank.h>
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <sys/resource.h>
#include <unistd.h>

SPANK_PLUGIN(spank_dynamic_alloc, 1);

static int gates_option = 0;

static struct spank_option spank_opts[] = {
    {"gates", "N", "Number of gates", 1, 0, NULL},
    SPANK_OPTIONS_TABLE_END
};

static int gates_opt_callback(int val, const char *optarg, int remote) {
    if (optarg) {
        gates_option = atoi(optarg);
        slurm_info("SPANK VERBOSE: gates_opt_callback fired with gates=%d", gates_option);
    }
    return 0;
}

int slurm_spank_init(spank_t sp, int ac, char **av) {
    slurm_info("SPANK VERBOSE: slurm_spank_init() called - Plugin loading");
    
    spank_option_register(sp, &spank_opts[0]);
    if (spank_opts[0].cb == NULL) {
        spank_opts[0].cb = (spank_opt_cb_f)gates_opt_callback;
    }
    
    slurm_info("SPANK VERBOSE: slurm_spank_init() complete - Options registered");
    return ESPANK_SUCCESS;
}

int slurm_spank_slurmd_init(spank_t sp, int ac, char **av) {
    slurm_info("SPANK VERBOSE: slurm_spank_slurmd_init() called");
    return ESPANK_SUCCESS;
}

int slurm_spank_job_prolog(spank_t sp, int ac, char **av) {
    uint32_t jobid = 0;
    spank_get_item(sp, S_JOB_ID, &jobid);
    slurm_info("SPANK VERBOSE: slurm_spank_job_prolog() called for job %u", jobid);
    return ESPANK_SUCCESS;
}

int slurm_spank_local_user_init(spank_t sp, int ac, char **av) {
    uint32_t jobid = 0;
    spank_get_item(sp, S_JOB_ID, &jobid);
    slurm_info("SPANK VERBOSE: slurm_spank_local_user_init() called for job %u", jobid);
    
    // Try to get gates from environment
    char *gates_env = getenv("DESIGN_GATES");
    if (gates_env) {
        gates_option = atoi(gates_env);
        slurm_info("SPANK VERBOSE: Got DESIGN_GATES=%d from environment", gates_option);
    }
    
    if (gates_option > 0) {
        slurm_info("SPANK VERBOSE: Processing gates=%d", gates_option);
        
        size_t base_mb = 2000;
        size_t calculated_mb = base_mb + (gates_option * 0.08);
        size_t buffer_mb = calculated_mb * 0.2;
        size_t total_mb = calculated_mb + buffer_mb;
        
        slurm_info("SPANK VERBOSE: Calculated memory: %zu MB (%.1f GB)", 
                   total_mb, total_mb / 1024.0);
        
        struct rlimit rlim;
        rlim.rlim_cur = total_mb * 1024 * 1024;
        rlim.rlim_max = total_mb * 1024 * 1024;
        
        if (setrlimit(RLIMIT_AS, &rlim) == 0) {
            slurm_info("SPANK VERBOSE: ✓ Set memory limit to %zu MB", total_mb);
        } else {
            slurm_error("SPANK VERBOSE: ✗ Failed to set memory limit");
        }
    }
    
    return ESPANK_SUCCESS;
}

int slurm_spank_task_init_privileged(spank_t sp, int ac, char **av) {
    uint32_t jobid = 0;
    spank_get_item(sp, S_JOB_ID, &jobid);
    slurm_info("SPANK VERBOSE: slurm_spank_task_init_privileged() called for job %u", jobid);
    return ESPANK_SUCCESS;
}

int slurm_spank_task_init(spank_t sp, int ac, char **av) {
    uint32_t jobid = 0;
    spank_get_item(sp, S_JOB_ID, &jobid);
    slurm_info("SPANK VERBOSE: slurm_spank_task_init() called for job %u", jobid);
    return ESPANK_SUCCESS;
}

int slurm_spank_task_post_fork(spank_t sp, int ac, char **av) {
    uint32_t jobid = 0;
    spank_get_item(sp, S_JOB_ID, &jobid);
    slurm_info("SPANK VERBOSE: slurm_spank_task_post_fork() called for job %u, PID=%d", 
               jobid, getpid());
    return ESPANK_SUCCESS;
}

int slurm_spank_task_exit(spank_t sp, int ac, char **av) {
    uint32_t jobid = 0;
    spank_get_item(sp, S_JOB_ID, &jobid);
    slurm_info("SPANK VERBOSE: slurm_spank_task_exit() called for job %u", jobid);
    return ESPANK_SUCCESS;
}

int slurm_spank_job_epilog(spank_t sp, int ac, char **av) {
    uint32_t jobid = 0;
    spank_get_item(sp, S_JOB_ID, &jobid);
    slurm_info("SPANK VERBOSE: slurm_spank_job_epilog() called for job %u", jobid);
    return ESPANK_SUCCESS;
}

int slurm_spank_exit(spank_t sp, int ac, char **av) {
    slurm_info("SPANK VERBOSE: slurm_spank_exit() called");
    return ESPANK_SUCCESS;
}
EOFCODE

echo "Compiling verbose plugin..."
gcc -shared -fPIC \
    -I/opt/slurm/include \
    -o spank_dynamic_alloc.so \
    spank_dynamic_alloc_verbose.c \
    -lpthread

if [ $? -ne 0 ]; then
    echo "✗ Compilation failed"
    exit 1
fi

echo "✓ Compiled"
echo ""

echo "Installing..."
sudo cp spank_dynamic_alloc.so /opt/slurm/lib/slurm/
sudo chmod 755 /opt/slurm/lib/slurm/spank_dynamic_alloc.so

echo "✓ Installed"
echo ""

echo "Restarting SLURM..."
sudo systemctl restart slurmctld
sleep 2

echo "✓ Complete"
echo ""
echo "════════════════════════════════════════════════════════════"
echo "  Verbose Plugin Installed"
echo "════════════════════════════════════════════════════════════"
echo ""
echo "This version logs EVERY hook that fires"
echo ""
echo "Test with:"
echo "  sbatch --export=ALL,DESIGN_GATES=100000 --mem=4096M \\"
echo "    --wrap='echo test; sleep 5'"
echo ""
echo "Check logs on compute node:"
echo "  ssh <compute-node> 'journalctl -u slurmd | grep VERBOSE'"
echo ""

cd $HOME
rm -rf $WORK_DIR
