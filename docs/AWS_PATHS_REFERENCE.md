# AWS Parallel Cluster - SLURM Paths Reference

## Important: AWS Parallel Cluster uses `/opt/slurm`, NOT `/etc/slurm`

## SLURM Paths on AWS Parallel Cluster

### Configuration Files
```
/opt/slurm/etc/
├── slurm.conf                    # Main SLURM configuration
├── job_submit.lua                # Job submit plugin (Lua)
├── plugstack.conf                # SPANK plugin configuration
└── scripts/
    └── prolog.d/                 # Prolog scripts directory
```

### Plugin Files
```
/opt/slurm/lib/slurm/
├── spank_monitor.so              # SPANK monitoring plugin
└── spank_dynamic_alloc.so        # SPANK dynamic allocation plugin
```

### Log Files
```
/var/log/slurm/
├── slurmctld.log                 # Controller logs (job_submit plugin logs here)
├── slurmd.log                    # Compute node daemon logs
└── slurm_jobacct.log             # Job accounting logs
```

### Include Paths (for compilation)
```
/opt/slurm/include/               # SLURM header files
/opt/slurm/include/slurm/         # SLURM API headers
```

## Quick Commands

### Check SLURM Configuration
```bash
# View SLURM config
cat /opt/slurm/etc/slurm.conf

# Check if job_submit plugin is enabled
grep "JobSubmitPlugins" /opt/slurm/etc/slurm.conf

# Validate SLURM config
sudo slurmctld -C
```

### Check Plugins
```bash
# Check job_submit plugin
ls -l /opt/slurm/etc/job_submit.lua

# Check SPANK plugins
ls -l /opt/slurm/lib/slurm/*.so

# Check SPANK config
cat /opt/slurm/etc/plugstack.conf
```

### Check Logs
```bash
# Controller logs (job_submit plugin)
sudo tail -f /var/log/slurm/slurmctld.log

# Filter for job_submit activity
sudo grep "job_submit" /var/log/slurm/slurmctld.log

# Compute node logs (SPANK plugins)
sudo tail -f /var/log/slurm/slurmd.log
```

## Installation Commands

### Install job_submit Plugin
```bash
# Copy plugin
sudo cp job_submit_learning.lua /opt/slurm/etc/job_submit.lua
sudo chown slurm:slurm /opt/slurm/etc/job_submit.lua
sudo chmod 644 /opt/slurm/etc/job_submit.lua

# Enable in SLURM config
echo "JobSubmitPlugins=lua" | sudo tee -a /opt/slurm/etc/slurm.conf

# Restart controller
sudo systemctl restart slurmctld
```

### Install SPANK Plugin
```bash
# Compile
gcc -shared -fPIC \
    -I/opt/slurm/include \
    -o spank_monitor.so \
    spank_monitor.c

# Install
sudo cp spank_monitor.so /opt/slurm/lib/slurm/
sudo chmod 755 /opt/slurm/lib/slurm/spank_monitor.so

# Configure
echo "required /opt/slurm/lib/slurm/spank_monitor.so" | \
    sudo tee /opt/slurm/etc/plugstack.conf

# Restart daemons
sudo systemctl restart slurmctld
sudo systemctl restart slurmd  # On compute nodes
```

## Common Mistakes

### ❌ Wrong Paths (Standard Linux)
```bash
/etc/slurm/slurm.conf              # Wrong on AWS
/etc/slurm/job_submit.lua          # Wrong on AWS
/usr/lib64/slurm/spank_monitor.so  # Wrong on AWS
```

### ✅ Correct Paths (AWS Parallel Cluster)
```bash
/opt/slurm/etc/slurm.conf          # Correct
/opt/slurm/etc/job_submit.lua      # Correct
/opt/slurm/lib/slurm/spank_monitor.so  # Correct
```

## NFS Mounts

On AWS Parallel Cluster, `/opt/slurm` is typically NFS-mounted from the head node to all compute nodes:

```bash
# Check NFS mounts
df -h | grep slurm

# Typical output:
# head-node:/opt/slurm  10G  2.1G  7.9G  21%  /opt/slurm
```

This means:
- ✅ Plugins installed on head node are automatically available on compute nodes
- ✅ Configuration changes propagate automatically
- ⚠️ Restart daemons after changes: `sudo systemctl restart slurmd`

## Verification Checklist

```bash
# 1. Check SLURM is using /opt/slurm
scontrol show config | grep SLURM_CONF
# Should show: /opt/slurm/etc/slurm.conf

# 2. Check job_submit plugin
ls -l /opt/slurm/etc/job_submit.lua
grep "JobSubmitPlugins=lua" /opt/slurm/etc/slurm.conf

# 3. Check SPANK plugins
ls -l /opt/slurm/lib/slurm/*.so
cat /opt/slurm/etc/plugstack.conf

# 4. Check logs
sudo tail -20 /var/log/slurm/slurmctld.log

# 5. Test job submission
sbatch --wrap="echo test" test.sh
```

## Summary

| Component | Standard Linux | AWS Parallel Cluster |
|-----------|---------------|---------------------|
| Config dir | `/etc/slurm/` | `/opt/slurm/etc/` |
| Plugin dir | `/usr/lib64/slurm/` | `/opt/slurm/lib/slurm/` |
| Log dir | `/var/log/` | `/var/log/slurm/` |
| Include dir | `/usr/include/slurm/` | `/opt/slurm/include/` |

**Always use `/opt/slurm` paths on AWS Parallel Cluster!**
