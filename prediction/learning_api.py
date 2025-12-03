#!/usr/bin/env python3
"""
Learning-based prediction API
Queries historical data and uses ML model for predictions
"""

from fastapi import FastAPI, HTTPException, Query
from pydantic import BaseModel
from typing import Optional, Dict
import sqlite3
from pathlib import Path
import pickle
import numpy as np

app = FastAPI(title="HPC Resource Learning API")

# Global model and database
MODEL_PATH = Path("models/resource_predictor.pkl")
DB_PATH = Path("data/metrics.db")

model = None
db_conn = None


class PredictionRequest(BaseModel):
    design_name: str
    cell_count: int
    stage_name: Optional[str] = "synthesis"
    clock_freq_mhz: Optional[float] = 100.0
    utilization: Optional[float] = 0.6


class PredictionResponse(BaseModel):
    memory_gb: float
    cpu_cores: int
    duration_sec: float
    confidence: str  # "high", "medium", "low", "default"
    source: str  # "model", "similar_job", "default"
    similar_jobs_count: int


@app.on_event("startup")
async def load_model():
    """Load ML model and connect to database"""
    global model, db_conn
    
    # Load model if exists
    if MODEL_PATH.exists():
        with open(MODEL_PATH, 'rb') as f:
            model_data = pickle.load(f)
            from prediction.model import ResourcePredictor
            model = ResourcePredictor()
            model.models = model_data['models']
            model.feature_names = model_data['feature_names']
            model.stages = model_data['stages']
        print(f"✓ Model loaded from {MODEL_PATH}")
    else:
        print(f"⚠ No model found at {MODEL_PATH}, using defaults")
    
    # Connect to database
    if DB_PATH.exists():
        db_conn = sqlite3.connect(str(DB_PATH), check_same_thread=False)
        print(f"✓ Database connected: {DB_PATH}")
    else:
        print(f"⚠ No database found at {DB_PATH}")


@app.get("/predict")
async def predict_resources(
    design_name: str = Query(..., description="Design name"),
    gates: int = Query(..., description="Number of gates"),
    stage: str = Query("synthesis", description="Stage name"),
    freq_mhz: float = Query(100.0, description="Clock frequency MHz")
) -> PredictionResponse:
    """
    Predict resource requirements based on historical data
    
    Strategy:
    1. Query database for similar jobs (same design, similar size)
    2. If found: Use actual data or ML model
    3. If not found: Return defaults with low confidence
    """
    
    # Step 1: Query for similar jobs
    similar_jobs = query_similar_jobs(design_name, gates, stage)
    
    if similar_jobs and len(similar_jobs) >= 3:
        # We have enough historical data
        avg_memory = np.mean([j['memory_peak_gb'] for j in similar_jobs])
        avg_cores = int(np.mean([j['cpu_cores'] for j in similar_jobs]))
        avg_duration = np.mean([j['duration_sec'] for j in similar_jobs])
        
        return PredictionResponse(
            memory_gb=round(avg_memory * 1.2, 2),  # 20% buffer
            cpu_cores=avg_cores,
            duration_sec=round(avg_duration, 1),
            confidence="high",
            source="similar_jobs",
            similar_jobs_count=len(similar_jobs)
        )
    
    # Step 2: Try ML model if available
    if model:
        design_features = {
            'cell_count': gates,
            'net_count': int(gates * 0.9),  # Estimate
            'die_area_um2': gates * 20,  # Estimate
            'utilization_target': 0.6,
            'clock_freq_mhz': freq_mhz,
            'clock_domains': 1,
            'technology_node_nm': 130,
            'metal_layers': 6,
            'clock_gating_enabled': False,
            'power_gating_enabled': False,
            'hierarchy_depth': 1,
            'macro_count': 0,
            'aspect_ratio': 1.0
        }
        
        tool_config = {'threads': 4}
        
        try:
            prediction = model.predict(stage, design_features, tool_config)
            
            confidence = "medium"
            if gates > 100000:  # Extrapolating
                confidence = "low"
            
            return PredictionResponse(
                memory_gb=round(prediction['memory_gb'] * 1.2, 2),
                cpu_cores=int(prediction['cpu_cores']),
                duration_sec=round(prediction['duration_sec'], 1),
                confidence=confidence,
                source="model",
                similar_jobs_count=len(similar_jobs) if similar_jobs else 0
            )
        except Exception as e:
            print(f"Model prediction failed: {e}")
    
    # Step 3: Return conservative defaults
    # Scale with design size
    default_memory = 4.0 + (gates / 50000) * 2.0  # 4GB base + 2GB per 50k gates
    
    return PredictionResponse(
        memory_gb=round(default_memory, 2),
        cpu_cores=4,
        duration_sec=600.0,
        confidence="low",
        source="default",
        similar_jobs_count=0
    )


def query_similar_jobs(design_name: str, gates: int, stage: str, tolerance: float = 0.3):
    """
    Query database for similar jobs
    
    Args:
        design_name: Design name
        gates: Number of gates
        stage: Stage name
        tolerance: Size tolerance (30% = ±30%)
    
    Returns:
        List of similar job records
    """
    if not db_conn:
        return []
    
    # Calculate size range
    min_gates = int(gates * (1 - tolerance))
    max_gates = int(gates * (1 + tolerance))
    
    query = """
    SELECT 
        j.job_name,
        df.cell_count,
        js.stage_name,
        js.duration_sec,
        sr.memory_peak_gb,
        sr.cpu_cores_used
    FROM jobs j
    JOIN design_features df ON j.id = df.job_id
    JOIN job_stages js ON j.id = js.job_id
    JOIN stage_resources sr ON js.id = sr.stage_id
    WHERE df.cell_count BETWEEN ? AND ?
    AND js.stage_name = ?
    AND j.status = 'completed'
    ORDER BY ABS(df.cell_count - ?) ASC
    LIMIT 10
    """
    
    try:
        cursor = db_conn.cursor()
        cursor.execute(query, (min_gates, max_gates, stage, gates))
        rows = cursor.fetchall()
        
        results = []
        for row in rows:
            results.append({
                'job_name': row[0],
                'cell_count': row[1],
                'stage_name': row[2],
                'duration_sec': row[3],
                'memory_peak_gb': row[4],
                'cpu_cores': row[5] or 4
            })
        
        return results
    except Exception as e:
        print(f"Database query failed: {e}")
        return []


@app.get("/stats")
async def get_stats():
    """Get database statistics"""
    if not db_conn:
        return {"error": "Database not connected"}
    
    try:
        cursor = db_conn.cursor()
        
        # Count jobs
        cursor.execute("SELECT COUNT(*) FROM jobs")
        job_count = cursor.fetchone()[0]
        
        # Count stages
        cursor.execute("SELECT COUNT(*) FROM job_stages")
        stage_count = cursor.fetchone()[0]
        
        # Get design size range
        cursor.execute("SELECT MIN(cell_count), MAX(cell_count) FROM design_features")
        min_cells, max_cells = cursor.fetchone()
        
        return {
            "total_jobs": job_count,
            "total_stages": stage_count,
            "design_size_range": {
                "min_cells": min_cells,
                "max_cells": max_cells
            },
            "model_loaded": model is not None
        }
    except Exception as e:
        return {"error": str(e)}


@app.get("/health")
async def health_check():
    """Health check endpoint"""
    return {
        "status": "healthy",
        "model_loaded": model is not None,
        "database_connected": db_conn is not None
    }


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
