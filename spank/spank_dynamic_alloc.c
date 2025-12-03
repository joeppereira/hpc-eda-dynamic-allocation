/*
 * spank_dynamic_alloc.c - SLURM SPANK plugin for dynamic memory allocation
 * 
 * Detects design parameters and adjusts memory limits at task launch
 */

#include <slurm/spank.h>
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <sys/resource.h>

SPANK_PLUGIN(spank_dynamic_alloc, 1);

/* Custom option for gate count */
static int gates_option = 0;

/* Option definition */
static struct spank_option spank_opts[] = {
    {
        "gates",
        "N",
        "Number of gates in design (for memory calculation)",
        1,  /* Takes argument */
        0,  /* Not required */
        NULL
    },
    SPANK_OPTIONS_TABLE_END
};

/*
 * Option callback - called when --gates=N is provided
 */
static int gates_opt_callback(int val, const char *optarg, int remote) {
    if (optarg) {
        gates_option = atoi(optarg);
        slurm_info("SPANK Dynamic: --gates=%d detected", gates_option);
    }
    return 0;
}

/*
 * Calculate memory requirement based on design size
 * Formula: base + (gates * factor) + 20% buffer
 */
static size_t calculate_memory_mb(int gates) {
    size_t base_mb = 2000;  /* 2GB base */
    size_t calculated_mb = base_mb + (gates * 0.08);  /* 80KB per gate */
    size_t buffer_mb = calculated_mb * 0.2;  /* 20% safety buffer */
    size_t total_mb = calculated_mb + buffer_mb;
    
    slurm_info("SPANK Dynamic: Memory calculation for %d gates:", gates);
    slurm_info("  Base: %zu MB", base_mb);
    slurm_info("  Calculated: %zu MB", calculated_mb);
    slurm_info("  Buffer (20%%): %zu MB", buffer_mb);
    slurm_info("  Total: %zu MB (%.1f GB)", total_mb, total_mb / 1024.0);
    
    return total_mb;
}

/*
 * Get current memory limit from SLURM
 */
static size_t get_slurm_mem_limit_mb(spank_t sp) {
    uint64_t mem_limit = 0;
    
    /* Try to get memory limit from SLURM */
    if (spank_get_item(sp, S_JOB_ALLOC_MEM, &mem_limit) == ESPANK_SUCCESS) {
        return (size_t)mem_limit;
    }
    
    /* Fallback: check environment variable */
    char *mem_env = getenv("SLURM_MEM_PER_NODE");
    if (mem_env) {
        return (size_t)atol(mem_env);
    }
    
    return 0;
}

/*
 * Set memory limit using setrlimit()
 */
static int set_memory_limit(size_t limit_mb) {
    struct rlimit rlim;
    size_t limit_bytes = limit_mb * 1024 * 1024;
    
    rlim.rlim_cur = limit_bytes;
    rlim.rlim_max = limit_bytes;
    
    if (setrlimit(RLIMIT_AS, &rlim) != 0) {
        slurm_error("SPANK Dynamic: Failed to set memory limit");
        return -1;
    }
    
    slurm_info("SPANK Dynamic: Memory limit set to %zu MB (%.1f GB)", 
               limit_mb, limit_mb / 1024.0);
    return 0;
}

/*
 * SPANK hook: Init - register options
 */
int slurm_spank_init(spank_t sp, int ac, char **av) {
    /* Register --gates option */
    spank_option_register(sp, &spank_opts[0]);
    
    /* Set callback for option */
    if (spank_opts[0].cb == NULL) {
        spank_opts[0].cb = (spank_opt_cb_f)gates_opt_callback;
    }
    
    slurm_info("SPANK Dynamic: Plugin initialized");
    return ESPANK_SUCCESS;
}

/*
 * SPANK hook: Task init privileged - runs before task starts (as root)
 * This is where we adjust memory limits
 */
int slurm_spank_task_init_privileged(spank_t sp, int ac, char **av) {
    uint32_t jobid = 0;
    size_t current_limit_mb, required_mb;
    
    /* Get job ID for logging */
    spank_get_item(sp, S_JOB_ID, &jobid);
    
    /* Check if --gates option was provided */
    if (gates_option == 0) {
        /* Try environment variable as fallback */
        char *gates_env = getenv("DESIGN_GATES");
        if (gates_env) {
            gates_option = atoi(gates_env);
            slurm_info("SPANK Dynamic: Using DESIGN_GATES=%d from environment", gates_option);
        } else {
            slurm_info("SPANK Dynamic: No --gates option or DESIGN_GATES env, skipping adjustment");
            return ESPANK_SUCCESS;
        }
    }
    
    /* Get current SLURM memory allocation */
    current_limit_mb = get_slurm_mem_limit_mb(sp);
    slurm_info("SPANK Dynamic: Job %u - Current SLURM allocation: %zu MB (%.1f GB)",
               jobid, current_limit_mb, current_limit_mb / 1024.0);
    
    /* Calculate required memory */
    required_mb = calculate_memory_mb(gates_option);
    
    /* Check if adjustment needed */
    if (required_mb > current_limit_mb) {
        size_t shortfall_mb = required_mb - current_limit_mb;
        slurm_info("SPANK Dynamic: ⚠️  Insufficient allocation detected!");
        slurm_info("  Current: %zu MB (%.1f GB)", current_limit_mb, current_limit_mb / 1024.0);
        slurm_info("  Required: %zu MB (%.1f GB)", required_mb, required_mb / 1024.0);
        slurm_info("  Shortfall: %zu MB (%.1f GB)", shortfall_mb, shortfall_mb / 1024.0);
        slurm_info("SPANK Dynamic: Adjusting memory limit...");
        
        /* Set new limit */
        if (set_memory_limit(required_mb) == 0) {
            slurm_info("SPANK Dynamic: ✓ Memory limit adjusted successfully");
            slurm_info("SPANK Dynamic: Job %u can now use up to %zu MB (%.1f GB)",
                       jobid, required_mb, required_mb / 1024.0);
        } else {
            slurm_error("SPANK Dynamic: ✗ Failed to adjust memory limit");
            return -1;
        }
    } else {
        slurm_info("SPANK Dynamic: ✓ Current allocation (%zu MB) is sufficient", current_limit_mb);
        slurm_info("SPANK Dynamic: Efficiency: %.1f%% (using %zu of %zu MB)",
                   (required_mb * 100.0) / current_limit_mb, required_mb, current_limit_mb);
    }
    
    return ESPANK_SUCCESS;
}

/*
 * SPANK hook: Task post fork - runs after task is forked
 */
int slurm_spank_task_post_fork(spank_t sp, int ac, char **av) {
    /* Log that task is starting with adjusted limits */
    if (gates_option > 0) {
        slurm_info("SPANK Dynamic: Task starting with adjusted memory limits for %d gates",
                   gates_option);
    }
    return ESPANK_SUCCESS;
}
