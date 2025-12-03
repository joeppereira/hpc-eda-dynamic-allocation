#!/usr/bin/env python3
"""
Database schema for storing job metrics and predictions
"""

from sqlalchemy import create_engine, Column, Integer, Float, String, DateTime, JSON, ForeignKey
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.orm import relationship, sessionmaker
from datetime import datetime

Base = declarative_base()


class Job(Base):
    """Job execution record"""
    __tablename__ = 'jobs'
    
    id = Column(Integer, primary_key=True)
    job_name = Column(String, nullable=False)
    workload_type = Column(String, default='EDA')  # EDA or HPC
    tool_name = Column(String, default='openroad')
    submit_time = Column(DateTime, default=datetime.utcnow)
    start_time = Column(DateTime)
    end_time = Column(DateTime)
    total_duration_sec = Column(Float)
    status = Column(String, default='completed')
    
    # SLURM configuration
    slurm_nodes = Column(Integer, default=1)
    slurm_cores = Column(Integer, default=4)
    slurm_memory_gb = Column(Float, default=16)
    
    # Relationships
    design_features = relationship("DesignFeatures", back_populates="job", uselist=False)
    tool_config = relationship("ToolConfig", back_populates="job", uselist=False)
    stages = relationship("JobStage", back_populates="job")


class DesignFeatures(Base):
    """Design-specific features (EDA)"""
    __tablename__ = 'design_features'
    
    id = Column(Integer, primary_key=True)
    job_id = Column(Integer, ForeignKey('jobs.id'))
    
    # Basic features
    cell_count = Column(Integer)
    net_count = Column(Integer)
    die_area_um2 = Column(Float)
    utilization_target = Column(Float)
    aspect_ratio = Column(Float, default=1.0)
    
    # Timing features
    clock_freq_mhz = Column(Float)
    clock_domains = Column(Integer, default=1)
    setup_slack_target_ps = Column(Float)
    
    # Technology features
    technology_node_nm = Column(Integer, default=130)
    metal_layers = Column(Integer, default=6)
    pdk = Column(String, default='sky130')
    
    # Power features
    clock_gating_enabled = Column(Integer, default=0)  # Boolean as int
    power_gating_enabled = Column(Integer, default=0)
    bias_threshold_gating = Column(Integer, default=0)
    multi_vt_cells = Column(String)  # JSON string
    
    # Complexity
    hierarchy_depth = Column(Integer)
    macro_count = Column(Integer, default=0)
    memory_instances = Column(Integer, default=0)
    
    # Relationship
    job = relationship("Job", back_populates="design_features")


class ToolConfig(Base):
    """Tool configuration parameters"""
    __tablename__ = 'tool_configs'
    
    id = Column(Integer, primary_key=True)
    job_id = Column(Integer, ForeignKey('jobs.id'))
    
    tool_name = Column(String)
    tool_version = Column(String)
    config_json = Column(JSON)  # Store arbitrary config as JSON
    
    # Relationship
    job = relationship("Job", back_populates="tool_config")


class JobStage(Base):
    """Individual stage within a job"""
    __tablename__ = 'job_stages'
    
    id = Column(Integer, primary_key=True)
    job_id = Column(Integer, ForeignKey('jobs.id'))
    
    stage_name = Column(String, nullable=False)
    stage_order = Column(Integer)
    start_time = Column(DateTime)
    end_time = Column(DateTime)
    duration_sec = Column(Float)
    
    # Relationships
    job = relationship("Job", back_populates="stages")
    resources = relationship("StageResources", back_populates="stage", uselist=False)


class StageResources(Base):
    """Resource usage for a stage"""
    __tablename__ = 'stage_resources'
    
    id = Column(Integer, primary_key=True)
    stage_id = Column(Integer, ForeignKey('job_stages.id'))
    
    # Compute metrics
    cpu_util_avg = Column(Float)
    cpu_util_peak = Column(Float)
    cpu_cores_used = Column(Integer)
    
    # Memory metrics
    memory_avg_gb = Column(Float)
    memory_peak_gb = Column(Float)
    
    # I/O metrics
    disk_read_gb = Column(Float)
    disk_write_gb = Column(Float)
    
    # Bottleneck
    bottleneck_type = Column(String)  # compute, memory, io, dependency
    bottleneck_severity = Column(Float)
    
    # Relationship
    stage = relationship("JobStage", back_populates="resources")


class Prediction(Base):
    """Prediction records for validation"""
    __tablename__ = 'predictions'
    
    id = Column(Integer, primary_key=True)
    job_id = Column(Integer, ForeignKey('jobs.id'))
    prediction_time = Column(DateTime, default=datetime.utcnow)
    
    # Predicted values
    predicted_cpu_cores = Column(Float)
    predicted_memory_gb = Column(Float)
    predicted_duration_sec = Column(Float)
    
    # Actual values (filled after job completes)
    actual_cpu_cores = Column(Float)
    actual_memory_gb = Column(Float)
    actual_duration_sec = Column(Float)
    
    # Accuracy metrics
    cpu_error_pct = Column(Float)
    memory_error_pct = Column(Float)
    duration_error_pct = Column(Float)


def init_database(db_path: str = 'sqlite:///data/metrics.db'):
    """Initialize database and create tables"""
    engine = create_engine(db_path, echo=False)
    Base.metadata.create_all(engine)
    return engine


def get_session(engine):
    """Get database session"""
    Session = sessionmaker(bind=engine)
    return Session()


if __name__ == "__main__":
    # Create database
    engine = init_database()
    print("Database initialized successfully")
    print(f"Tables created: {', '.join(Base.metadata.tables.keys())}")
