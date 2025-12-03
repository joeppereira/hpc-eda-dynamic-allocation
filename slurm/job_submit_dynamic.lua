--[[
 SLURM Job Submit Plugin - Dynamic Memory Allocation
 
 This is the RECOMMENDED way to modify job resources in modern SLURM.
 Runs at job submission time, before scheduling.
 
 Install: Copy to /opt/slurm/etc/job_submit.lua
 Configure: Add "JobSubmitPlugins=lua" to slurm.conf
--]]

function slurm_job_submit(job_desc, part_list, submit_uid)
    -- Get DESIGN_GATES from environment
    local gates = job_desc.environment["DESIGN_GATES"]
    
    if gates == nil or gates == "" then
        -- No DESIGN_GATES specified, don't modify
        return slurm.SUCCESS
    end
    
    gates = tonumber(gates)
    if gates == nil or gates <= 0 then
        slurm.log_info("job_submit: Invalid DESIGN_GATES value")
        return slurm.SUCCESS
    end
    
    -- Calculate required memory (same formula)
    local base_mb = 2000
    local calculated_mb = base_mb + (gates * 0.08)
    local buffer_mb = calculated_mb * 0.2
    local required_mb = math.floor(calculated_mb + buffer_mb)
    
    -- Get current memory request
    local current_mb = job_desc.min_mem_per_node or 0
    
    slurm.log_info(string.format(
        "job_submit: Job %d, DESIGN_GATES=%d, calculated=%d MB, current=%d MB",
        job_desc.job_id or 0, gates, required_mb, current_mb
    ))
    
    -- Adjust if needed
    if required_mb > current_mb then
        job_desc.min_mem_per_node = required_mb
        slurm.log_info(string.format(
            "job_submit: Adjusted memory from %d MB to %d MB",
            current_mb, required_mb
        ))
    else
        slurm.log_info(string.format(
            "job_submit: Current allocation (%d MB) is sufficient",
            current_mb
        ))
    end
    
    return slurm.SUCCESS
end

function slurm_job_modify(job_desc, job_rec, part_list, modify_uid)
    -- Called when job is modified
    return slurm.SUCCESS
end

return slurm.SUCCESS
