#!/bin/bash
# Install SLURM Job Submit Plugin (RECOMMENDED APPROACH)

set -e

echo "════════════════════════════════════════════════════════════"
echo "  SLURM Job Submit Plugin - Dynamic Memory Allocation"
echo "  (This is the RECOMMENDED way for modern SLURM)"
echo "════════════════════════════════════════════════════════════"
echo ""

# Create job_submit plugin inline
echo "Creating job_submit plugin..."
sudo tee /opt/slurm/etc/job_submit.lua > /dev/null << 'EOFLUA'
-- SLURM Job Submit Plugin - Dynamic Memory Allocation

function slurm_job_submit(job_desc, part_list, submit_uid)
    local gates = job_desc.environment["DESIGN_GATES"]
    
    if gates == nil or gates == "" then
        return slurm.SUCCESS
    end
    
    gates = tonumber(gates)
    if gates == nil or gates <= 0 then
        return slurm.SUCCESS
    end
    
    -- Calculate memory: base + (gates * 0.08) + 20% buffer
    local base_mb = 2000
    local calculated_mb = base_mb + (gates * 0.08)
    local buffer_mb = calculated_mb * 0.2
    local required_mb = math.floor(calculated_mb + buffer_mb)
    
    local current_mb = job_desc.min_mem_per_node or 0
    
    slurm.log_info(string.format(
        "job_submit: DESIGN_GATES=%d, need=%d MB, have=%d MB",
        gates, required_mb, current_mb
    ))
    
    if required_mb > current_mb then
        job_desc.min_mem_per_node = required_mb
        slurm.log_info(string.format(
            "job_submit: ✓ Adjusted %d MB → %d MB",
            current_mb, required_mb
        ))
    end
    
    return slurm.SUCCESS
end

function slurm_job_modify(job_desc, job_rec, part_list, modify_uid)
    return slurm.SUCCESS
end

return slurm.SUCCESS
EOFLUA

sudo chmod 644 /opt/slurm/etc/job_submit.lua
echo "✓ Plugin created"
echo ""

echo "Checking slurm.conf..."
if grep -q "^JobSubmitPlugins=lua" /opt/slurm/etc/slurm.conf; then
    echo "✓ JobSubmitPlugins already configured"
else
    echo "⚠  Need to add JobSubmitPlugins=lua to slurm.conf"
    echo ""
    echo "Run this command:"
    echo "  sudo bash -c 'echo \"JobSubmitPlugins=lua\" >> /opt/slurm/etc/slurm.conf'"
    echo "  sudo systemctl restart slurmctld"
fi

echo ""
echo "════════════════════════════════════════════════════════════"
echo "  Installation Complete"
echo "════════════════════════════════════════════════════════════"
echo ""
echo "This is the OFFICIAL SLURM way to modify job resources!"
echo ""
echo "Advantages over SPANK/Prolog:"
echo "  ✓ Modifies job BEFORE scheduling"
echo "  ✓ Works with cgroups"
echo "  ✓ Officially supported"
echo "  ✓ Simpler than SPANK"
echo ""
echo "Test:"
echo "  sbatch --export=ALL,DESIGN_GATES=100000 --mem=4096M test.sh"
echo ""
echo "Check logs:"
echo "  grep job_submit /var/log/slurmctld.log"
echo ""
