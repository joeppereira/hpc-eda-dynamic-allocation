/*
 * spank_monitor.c - SLURM SPANK plugin for HPC resource monitoring
 * 
 * Monitors CPU, memory, and I/O for each job and exports metrics
 * to JSON format for ML model training.
 */

#include <slurm/spank.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <pthread.h>
#include <time.h>
#include <sys/types.h>
#include <sys/stat.h>

SPANK_PLUGIN(spank_monitor, 1);

/* Plugin metadata */
const char plugin_name[] = "spank_monitor";
const char plugin_type[] = "spank";
const unsigned int plugin_version = 1;
const unsigned int spank_plugin_version = 1;

/* Global state */
static pthread_t monitor_thread;
static volatile int job_running = 0;
static char metrics_file[512];
static FILE *metrics_fp = NULL;
static uint32_t current_jobid = 0;

/* Design features from environment variables */
typedef struct {
    int cell_count;
    int net_count;
    long die_area_um2;
    float utilization_target;
    int clock_freq_mhz;
    int technology_node_nm;
} design_features_t;

static design_features_t design_features = {0};

/* Resource sample */
typedef struct {
    time_t timestamp;
    long cpu_utime;
    long cpu_stime;
    long memory_rss;
    long memory_vsize;
    long io_read_bytes;
    long io_write_bytes;
} resource_sample_t;

/*
 * Read /proc/[pid]/stat for CPU metrics
 */
static int read_proc_stat(pid_t pid, long *utime, long *stime, long *rss, long *vsize) {
    char path[256];
    FILE *fp;
    
    snprintf(path, sizeof(path), "/proc/%d/stat", pid);
    fp = fopen(path, "r");
    if (!fp) return -1;
    
    /* Parse /proc/[pid]/stat - see proc(5) man page */
    fscanf(fp, "%*d %*s %*c %*d %*d %*d %*d %*d %*u %*u %*u %*u %*u %ld %ld %*d %*d %*d %*d %*d %*d %*u %ld %ld",
           utime, stime, vsize, rss);
    
    fclose(fp);
    return 0;
}

/*
 * Read /proc/[pid]/io for I/O metrics
 */
static int read_proc_io(pid_t pid, long *read_bytes, long *write_bytes) {
    char path[256];
    FILE *fp;
    char line[256];
    
    snprintf(path, sizeof(path), "/proc/%d/io", pid);
    fp = fopen(path, "r");
    if (!fp) return -1;
    
    *read_bytes = 0;
    *write_bytes = 0;
    
    while (fgets(line, sizeof(line), fp)) {
        if (strncmp(line, "read_bytes:", 11) == 0) {
            sscanf(line + 11, "%ld", read_bytes);
        } else if (strncmp(line, "write_bytes:", 12) == 0) {
            sscanf(line + 12, "%ld", write_bytes);
        }
    }
    
    fclose(fp);
    return 0;
}

/*
 * Monitoring thread - samples resources every second
 */
static void* monitor_resources(void* arg) {
    pid_t pid = getpid();
    resource_sample_t sample;
    int sample_count = 0;
    
    slurm_info("SPANK Monitor: Starting monitoring thread for PID %d", pid);
    
    while (job_running) {
        /* Collect resource sample */
        sample.timestamp = time(NULL);
        
        if (read_proc_stat(pid, &sample.cpu_utime, &sample.cpu_stime, 
                          &sample.memory_rss, &sample.memory_vsize) == 0) {
            
            read_proc_io(pid, &sample.io_read_bytes, &sample.io_write_bytes);
            
            /* Write sample to metrics file */
            if (metrics_fp) {
                if (sample_count > 0) fprintf(metrics_fp, ",\n");
                
                fprintf(metrics_fp, 
                    "    {\"timestamp\":%ld,\"cpu_utime\":%ld,\"cpu_stime\":%ld,"
                    "\"memory_rss\":%ld,\"memory_vsize\":%ld,"
                    "\"io_read\":%ld,\"io_write\":%ld}",
                    sample.timestamp, sample.cpu_utime, sample.cpu_stime,
                    sample.memory_rss, sample.memory_vsize,
                    sample.io_read_bytes, sample.io_write_bytes);
                
                fflush(metrics_fp);
                sample_count++;
            }
        }
        
        sleep(1);  /* Sample every second */
    }
    
    slurm_info("SPANK Monitor: Monitoring thread stopped, collected %d samples", sample_count);
    return NULL;
}

/*
 * Read design features from environment variables
 */
static void read_design_features(void) {
    char *env_val;
    
    if ((env_val = getenv("DESIGN_CELL_COUNT")))
        design_features.cell_count = atoi(env_val);
    
    if ((env_val = getenv("DESIGN_NET_COUNT")))
        design_features.net_count = atoi(env_val);
    
    if ((env_val = getenv("DESIGN_DIE_AREA")))
        design_features.die_area_um2 = atol(env_val);
    
    if ((env_val = getenv("DESIGN_UTIL")))
        design_features.utilization_target = atof(env_val);
    
    if ((env_val = getenv("DESIGN_FREQ_MHZ")))
        design_features.clock_freq_mhz = atoi(env_val);
    
    if ((env_val = getenv("DESIGN_TECH_NODE")))
        design_features.technology_node_nm = atoi(env_val);
    
    slurm_info("SPANK Monitor: Design features - cells=%d, freq=%dMHz, util=%.2f",
               design_features.cell_count, design_features.clock_freq_mhz,
               design_features.utilization_target);
}

/*
 * SPANK hook: Job prolog (runs before job starts on compute node)
 */
int slurm_spank_job_prolog(spank_t sp, int ac, char **av) {
    char job_name[256];
    
    /* Get job ID */
    if (spank_get_item(sp, S_JOB_ID, &current_jobid) != ESPANK_SUCCESS) {
        slurm_error("SPANK Monitor: Failed to get job ID");
        return -1;
    }
    
    /* Get job name */
    if (spank_getenv(sp, "SLURM_JOB_NAME", job_name, sizeof(job_name)) != ESPANK_SUCCESS) {
        snprintf(job_name, sizeof(job_name), "job_%u", current_jobid);
    }
    
    /* Read design features from environment */
    read_design_features();
    
    /* Create metrics directory if it doesn't exist */
    mkdir("/shared/metrics", 0755);
    
    /* Open metrics file */
    snprintf(metrics_file, sizeof(metrics_file), 
             "/shared/metrics/job_%u.json", current_jobid);
    
    metrics_fp = fopen(metrics_file, "w");
    if (!metrics_fp) {
        slurm_error("SPANK Monitor: Failed to open metrics file: %s", metrics_file);
        return -1;
    }
    
    /* Write JSON header with design features */
    fprintf(metrics_fp, "{\n");
    fprintf(metrics_fp, "  \"job_id\": %u,\n", current_jobid);
    fprintf(metrics_fp, "  \"job_name\": \"%s\",\n", job_name);
    fprintf(metrics_fp, "  \"start_time\": %ld,\n", time(NULL));
    fprintf(metrics_fp, "  \"design_features\": {\n");
    fprintf(metrics_fp, "    \"cell_count\": %d,\n", design_features.cell_count);
    fprintf(metrics_fp, "    \"net_count\": %d,\n", design_features.net_count);
    fprintf(metrics_fp, "    \"die_area_um2\": %ld,\n", design_features.die_area_um2);
    fprintf(metrics_fp, "    \"utilization_target\": %.2f,\n", design_features.utilization_target);
    fprintf(metrics_fp, "    \"clock_freq_mhz\": %d,\n", design_features.clock_freq_mhz);
    fprintf(metrics_fp, "    \"technology_node_nm\": %d\n", design_features.technology_node_nm);
    fprintf(metrics_fp, "  },\n");
    fprintf(metrics_fp, "  \"samples\": [\n");
    
    fflush(metrics_fp);
    
    slurm_info("SPANK Monitor: Job %u started, monitoring to %s", current_jobid, metrics_file);
    return ESPANK_SUCCESS;
}

/*
 * SPANK hook: Task post-fork (runs after task process is forked)
 */
int slurm_spank_task_post_fork(spank_t sp, int ac, char **av) {
    /* Start monitoring thread */
    job_running = 1;
    
    if (pthread_create(&monitor_thread, NULL, monitor_resources, NULL) != 0) {
        slurm_error("SPANK Monitor: Failed to create monitoring thread");
        return -1;
    }
    
    slurm_info("SPANK Monitor: Monitoring thread started for job %u", current_jobid);
    return ESPANK_SUCCESS;
}

/*
 * SPANK hook: Task exit (runs when task process exits)
 */
int slurm_spank_task_exit(spank_t sp, int ac, char **av) {
    /* Stop monitoring thread */
    job_running = 0;
    
    if (pthread_join(monitor_thread, NULL) != 0) {
        slurm_error("SPANK Monitor: Failed to join monitoring thread");
    }
    
    slurm_info("SPANK Monitor: Monitoring thread stopped for job %u", current_jobid);
    return ESPANK_SUCCESS;
}

/*
 * SPANK hook: Job epilog (runs after job completes on compute node)
 */
int slurm_spank_job_epilog(spank_t sp, int ac, char **av) {
    /* Close metrics file */
    if (metrics_fp) {
        fprintf(metrics_fp, "\n  ],\n");
        fprintf(metrics_fp, "  \"end_time\": %ld\n", time(NULL));
        fprintf(metrics_fp, "}\n");
        fclose(metrics_fp);
        metrics_fp = NULL;
    }
    
    slurm_info("SPANK Monitor: Job %u completed, metrics saved to %s", 
               current_jobid, metrics_file);
    
    return ESPANK_SUCCESS;
}

/*
 * SPANK hook: Init (runs when plugin is loaded)
 */
int slurm_spank_init(spank_t sp, int ac, char **av) {
    slurm_info("SPANK Monitor: Plugin initialized (version %u)", plugin_version);
    return ESPANK_SUCCESS;
}
