# Requirements Document

## Introduction

This system optimizes HPC/EDA workload resource allocation on AWS Parallel Cluster using SLURM scheduling and SPANK plugin monitoring. The goal is to predict optimal resource requirements for jobs based on historical execution data, reducing waste and improving cluster efficiency.

## Glossary

- **System**: The HPC Resource Optimization System
- **SLURM**: Simple Linux Utility for Resource Management - the job scheduler
- **SPANK Plugin**: SLURM Plugin Architecture for Node and job (K)control - custom monitoring plugin
- **OpenROAD**: Open-source RTL-to-GDSII digital design flow tool
- **Stage**: A distinct phase within a job execution (e.g., placement, routing)
- **Design Features**: Characteristics of an EDA design (cell count, frequency, utilization)
- **Resource Profile**: CPU, memory, I/O, and duration metrics for a job stage
- **Prediction Engine**: ML model that predicts resource requirements
- **Job Optimizer**: Service that modifies SLURM job submissions based on predictions

## Requirements

### Requirement 1: Real Workload Execution

**User Story:** As a system developer, I want to use actual tool execution data, so that predictions are based on real behavior rather than simulations.

#### Acceptance Criteria

1. WHEN the System collects training data, THE System SHALL execute actual OpenROAD binary on real designs
2. WHEN the System detects job stages, THE System SHALL parse actual tool log files for stage markers
3. WHEN the System captures resource metrics, THE System SHALL monitor real process resource consumption via system APIs
4. IF the System detects simulated or mock data, THEN THE System SHALL reject the data from the training set
5. WHEN the System validates collected data, THE System SHALL verify that stage names match actual OpenROAD stages

### Requirement 2: Lightweight Log Processing

**User Story:** As a cluster administrator, I want log processing to have minimal overhead, so that monitoring doesn't impact job performance.

#### Acceptance Criteria

1. WHEN the System processes logs, THE System SHALL detect stage transitions within 100 milliseconds of log write
2. WHILE the System monitors a job, THE System SHALL consume less than 1% CPU overhead per monitored job
3. WHILE the System monitors a job, THE System SHALL use less than 10MB memory per monitored job
4. THE System SHALL process logs locally on compute nodes without external transmission
5. THE System SHALL process more than 10000 log lines per second

### Requirement 3: SPANK Plugin Resource Monitoring

**User Story:** As a data scientist, I want fine-grained per-stage resource metrics, so that I can train accurate prediction models.

#### Acceptance Criteria

1. WHEN a SLURM job executes, THE SPANK Plugin SHALL capture CPU utilization per stage
2. WHEN a SLURM job executes, THE SPANK Plugin SHALL capture memory usage per stage
3. WHEN a SLURM job executes, THE SPANK Plugin SHALL capture disk I/O per stage
4. WHEN a SLURM job executes, THE SPANK Plugin SHALL associate metrics with detected stages
5. WHEN the SPANK Plugin completes monitoring, THE SPANK Plugin SHALL export metrics in structured JSON format

### Requirement 4: Stage Detection from Tool Logs

**User Story:** As a monitoring system, I want to automatically detect job stages from tool output, so that I can correlate resources with specific workflow phases.

#### Acceptance Criteria

1. WHEN OpenROAD writes log output, THE System SHALL detect stage start markers in real-time
2. WHEN OpenROAD writes log output, THE System SHALL detect stage end markers in real-time
3. WHEN the System detects a stage transition, THE System SHALL record the timestamp with nanosecond precision
4. THE System SHALL achieve stage detection accuracy greater than 95%
5. WHEN the System detects stages, THE System SHALL maintain a state machine for stage transitions

### Requirement 5: Design Feature Extraction

**User Story:** As a prediction model, I want design characteristics extracted from tool logs, so that I can correlate features with resource requirements.

#### Acceptance Criteria

1. WHEN OpenROAD completes a job, THE System SHALL extract cell count from log files
2. WHEN OpenROAD completes a job, THE System SHALL extract net count from log files
3. WHEN OpenROAD completes a job, THE System SHALL extract die area from log files
4. WHEN OpenROAD completes a job, THE System SHALL extract utilization target from log files
5. WHEN OpenROAD completes a job, THE System SHALL extract clock frequency from constraint files

### Requirement 6: Historical Database Storage

**User Story:** As a system operator, I want all job execution data stored in a queryable database, so that I can analyze trends and train models.

#### Acceptance Criteria

1. WHEN the System receives job metrics, THE System SHALL store design features in the database
2. WHEN the System receives job metrics, THE System SHALL store per-stage resource profiles in the database
3. WHEN the System receives job metrics, THE System SHALL store tool configuration in the database
4. WHEN the System stores data, THE System SHALL validate that resource values are within realistic bounds
5. WHEN the System stores data, THE System SHALL record provenance information including SLURM job ID and timestamp

### Requirement 7: Prediction Model Training

**User Story:** As a data scientist, I want to train regression models on historical data, so that I can predict resource requirements for new jobs.

#### Acceptance Criteria

1. WHEN the System trains a model, THE System SHALL use only real execution data from the database
2. WHEN the System trains a model, THE System SHALL create separate models per job stage
3. WHEN the System trains a model, THE System SHALL validate prediction accuracy on held-out test data
4. WHEN the System evaluates a model, THE System SHALL achieve prediction accuracy greater than 85%
5. IF the System detects simulated data in training set, THEN THE System SHALL reject the model

### Requirement 8: Prediction API Service

**User Story:** As a job optimizer, I want to query predicted resource requirements via API, so that I can modify job submissions.

#### Acceptance Criteria

1. WHEN the Prediction API receives design features, THE Prediction API SHALL return predicted CPU requirements per stage
2. WHEN the Prediction API receives design features, THE Prediction API SHALL return predicted memory requirements per stage
3. WHEN the Prediction API receives design features, THE Prediction API SHALL return predicted duration per stage
4. WHEN the Prediction API processes a request, THE Prediction API SHALL respond within 100 milliseconds
5. THE Prediction API SHALL handle concurrent requests from multiple clients

### Requirement 9: Dynamic Resource Allocation

**User Story:** As a cluster user, I want my jobs to automatically receive optimal resource allocations, so that I don't waste resources or experience failures.

#### Acceptance Criteria

1. WHEN a user submits a SLURM job, THE Job Optimizer SHALL intercept the submission
2. WHEN the Job Optimizer intercepts a job, THE Job Optimizer SHALL query the Prediction API with job parameters
3. WHEN the Job Optimizer receives predictions, THE Job Optimizer SHALL modify the SLURM job script with predicted resources
4. WHEN the Job Optimizer submits the modified job, THE Job Optimizer SHALL track actual versus predicted performance
5. WHEN a job completes, THE System SHALL verify that predicted resources were within 20% of actual usage

### Requirement 10: Prediction Validation

**User Story:** As a system operator, I want to continuously validate prediction accuracy, so that I can detect model drift and retrain when needed.

#### Acceptance Criteria

1. WHEN a job completes, THE System SHALL compare predicted resources to actual usage
2. WHEN a job completes, THE System SHALL log prediction error metrics
3. WHEN the System detects prediction accuracy below 85%, THE System SHALL alert operators
4. THE System SHALL track prediction accuracy trends over time
5. THE System SHALL support periodic model retraining with new data

### Requirement 11: Cluster Deployment

**User Story:** As a DevOps engineer, I want to deploy the system on AWS Parallel Cluster, so that it runs in a production HPC environment.

#### Acceptance Criteria

1. WHEN deploying the cluster, THE System SHALL configure SLURM scheduler with appropriate partitions
2. WHEN deploying the cluster, THE System SHALL install the SPANK plugin on all compute nodes
3. WHEN deploying the cluster, THE System SHALL configure SLURM to load the SPANK plugin at job start
4. WHEN deploying the cluster, THE System SHALL install OpenROAD and required PDKs
5. WHEN the cluster starts, THE System SHALL verify that the SPANK plugin loads without errors

### Requirement 12: End-to-End Testing

**User Story:** As a QA engineer, I want to run comprehensive tests comparing baseline and optimized jobs, so that I can validate efficiency improvements.

#### Acceptance Criteria

1. WHEN running baseline tests, THE System SHALL execute jobs with conservative resource allocations
2. WHEN running optimized tests, THE System SHALL execute jobs with predicted resource allocations
3. WHEN tests complete, THE System SHALL calculate efficiency improvement percentage
4. WHEN tests complete, THE System SHALL generate a performance comparison report
5. THE System SHALL demonstrate average efficiency improvement greater than 15%
