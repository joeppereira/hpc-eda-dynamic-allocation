#!/usr/bin/env python3
"""
FastAPI prediction service
"""

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
from typing import Dict, Optional
from pathlib import Path
from model import ResourcePredictor

app = FastAPI(title="Resource Prediction API", version="1.0.0")

# Load model at startup
model_path = Path("prediction/trained_model.pkl")
predictor = None

@app.on_event("startup")
async def load_model():
    global predictor
    if model_path.exists():
        predictor = ResourcePredictor.load(model_path)
        print(f"Model loaded from {model_path}")
        print(f"Available stages: {predictor.stages}")
    else:
        print(f"Warning: Model not found at {model_path}")
        print("Train a model first using: python prediction/train_model.py")


class DesignFeatures(BaseModel):
    cell_count: int
    net_count: int
    die_area_um2: float
    utilization_target: float = 0.6
    aspect_ratio: float = 1.0
    clock_freq_mhz: float = 100
    clock_domains: int = 1
    technology_node_nm: int = 130
    metal_layers: int = 6
    clock_gating_enabled: bool = False
    power_gating_enabled: bool = False
    hierarchy_depth: int = 1
    macro_count: int = 0


class ToolConfig(BaseModel):
    tool: str = "openroad"
    threads: int = 4
    version: Optional[str] = None


class PredictionRequest(BaseModel):
    stage_name: str
    design_features: DesignFeatures
    tool_config: ToolConfig


class PredictionResponse(BaseModel):
    stage_name: str
    predicted_cpu_cores: float
    predicted_memory_gb: float
    predicted_duration_sec: float
    confidence: str = "medium"


@app.get("/")
async def root():
    return {
        "service": "Resource Prediction API",
        "version": "1.0.0",
        "status": "running" if predictor else "model not loaded"
    }


@app.get("/health")
async def health():
    return {
        "status": "healthy" if predictor else "model not loaded",
        "model_loaded": predictor is not None,
        "available_stages": predictor.stages if predictor else []
    }


@app.post("/predict", response_model=PredictionResponse)
async def predict(request: PredictionRequest):
    """
    Predict resource requirements for a job stage
    
    Args:
        request: Prediction request with design features and tool config
        
    Returns:
        Predicted CPU cores, memory, and duration
    """
    if not predictor:
        raise HTTPException(status_code=503, detail="Model not loaded")
    
    # Convert Pydantic models to dicts
    design_features = request.design_features.dict()
    tool_config = request.tool_config.dict()
    
    # Make prediction
    try:
        predictions = predictor.predict(
            request.stage_name,
            design_features,
            tool_config
        )
        
        return PredictionResponse(
            stage_name=request.stage_name,
            predicted_cpu_cores=predictions['cpu_cores'],
            predicted_memory_gb=predictions['memory_gb'],
            predicted_duration_sec=predictions['duration_sec']
        )
    
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Prediction failed: {str(e)}")


@app.post("/predict_all_stages")
async def predict_all_stages(design_features: DesignFeatures, tool_config: ToolConfig):
    """
    Predict resources for all stages of a design
    
    Returns:
        Dictionary of predictions per stage
    """
    if not predictor:
        raise HTTPException(status_code=503, detail="Model not loaded")
    
    design_dict = design_features.dict()
    tool_dict = tool_config.dict()
    
    predictions = {}
    for stage in predictor.stages:
        try:
            pred = predictor.predict(stage, design_dict, tool_dict)
            predictions[stage] = pred
        except Exception as e:
            predictions[stage] = {"error": str(e)}
    
    return {
        "design_features": design_dict,
        "predictions": predictions,
        "total_estimated_duration": sum(
            p.get('duration_sec', 0) for p in predictions.values() if 'duration_sec' in p
        )
    }


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
