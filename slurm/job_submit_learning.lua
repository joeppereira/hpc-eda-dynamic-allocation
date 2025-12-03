--[[
Learning-based job_submit plugin for SLURM
Queries historical data to adjust resource allocation

Flow:
1. Check if similar job exists in database
2. If yes: Use ML prediction to adjust resources
3. If no: Let job run with user request, monitor will collect data
]]

function slurm_job_submit(job_desc, part_list, submit_uid)
    -- Get design parameters from environment
    local design_gates = job_desc.environment["DESIGN_GATES"]
    local design_name = job_desc.environment["DESIGN_NAME"]
    local stage_name = job_desc.environment["STAGE_NAME"]
    
    if not design_gates or not design_name then
        -- No design info, let it run as-is
        slurm.log_info("job_submit: No design parameters, using user request")
        return slurm.SUCCESS
    end
    
    slurm.log_info(string.format(
        "job_submit: Job %s, Design=%s, Gates=%s, Stage=%s",
        job_desc.name or "unknown",
        design_name,
        design_gates,
        stage_name or "unknown"
    ))
    
    -- Query prediction API for similar jobs
    local prediction = query_prediction_api(design_name, design_gates, stage_name)
    
    if prediction then
        -- We have historical data, adjust resources
        local predicted_mem_mb = math.floor(prediction.memory_gb * 1024)
        local predicted_cores = math.floor(prediction.cpu_cores)
        
        slurm.log_info(string.format(
            "job_submit: Prediction found - Memory: %d MB, Cores: %d (confidence: %s)",
            predicted_mem_mb,
            predicted_cores,
            prediction.confidence or "unknown"
        ))
        
        -- Only adjust if prediction is confident and significantly different
        if prediction.confidence ~= "low" then
            local original_mem = job_desc.min_mem_per_node or 4096
            
            if predicted_mem_mb > original_mem * 1.2 then
                slurm.log_info(string.format(
                    "job_submit: Adjusting memory %d -> %d MB (based on history)",
                    original_mem,
                    predicted_mem_mb
                ))
                job_desc.min_mem_per_node = predicted_mem_mb
            end
            
            if predicted_cores > (job_desc.min_cpus or 1) then
                slurm.log_info(string.format(
                    "job_submit: Adjusting cores %d -> %d (based on history)",
                    job_desc.min_cpus or 1,
                    predicted_cores
                ))
                job_desc.min_cpus = predicted_cores
            end
        end
    else
        -- No historical data, let it run and learn
        slurm.log_info(string.format(
            "job_submit: No prediction available for %s/%s, will learn from this run",
            design_name,
            stage_name or "all"
        ))
    end
    
    return slurm.SUCCESS
end

function query_prediction_api(design_name, design_gates, stage_name)
    --[[
    Query the prediction API for resource estimates
    Returns: {memory_gb, cpu_cores, confidence} or nil
    ]]
    
    -- Build API request
    local api_url = os.getenv("PREDICTION_API_URL") or "http://localhost:8000"
    local endpoint = string.format(
        "%s/predict?design_name=%s&gates=%s&stage=%s",
        api_url,
        design_name,
        design_gates,
        stage_name or "synthesis"
    )
    
    -- Use curl to query API (simple approach)
    local cmd = string.format(
        "curl -s -m 2 '%s' 2>/dev/null",
        endpoint
    )
    
    local handle = io.popen(cmd)
    if not handle then
        return nil
    end
    
    local response = handle:read("*a")
    handle:close()
    
    if not response or response == "" then
        return nil
    end
    
    -- Parse JSON response (simple parsing)
    local memory_gb = response:match('"memory_gb"%s*:%s*([%d%.]+)')
    local cpu_cores = response:match('"cpu_cores"%s*:%s*([%d%.]+)')
    local confidence = response:match('"confidence"%s*:%s*"([^"]+)"')
    
    if memory_gb and cpu_cores then
        return {
            memory_gb = tonumber(memory_gb),
            cpu_cores = tonumber(cpu_cores),
            confidence = confidence
        }
    end
    
    return nil
end

function slurm_job_modify(job_desc, job_rec, part_list, modify_uid)
    return slurm.SUCCESS
end

slurm.log_info("job_submit_learning.lua loaded - Learning-based resource allocation enabled")
return slurm.SUCCESS
