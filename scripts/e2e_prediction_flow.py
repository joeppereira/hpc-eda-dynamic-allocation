#!/usr/bin/env python3
"""
End-to-End Prediction Flow Test

This script demonstrates the complete flow:
1. Before job start: Predict resources based on design features
2. During job: Monitor actual resource usage at each stage
3. After each stage: Compare prediction vs actual
4. Modify SLURM job: Adjust resources for remaining stages

Flow: Design → Prediction → SLURM Job → SPANK Monitor → Update Prediction
"""

import sys
import json
import time
from pathlib import Path
from typing import Dict, List
from datetime import datetime

# Add parent to path
sys.path.append(str(Path(__file__).parent.parent))

from prediction.model import ResourcePredictor


class PredictionFlowTest:
    """Complete prediction and SLURM modification flow"""
    
    def __init__(self, model_path: Path):
        self.model_path = model_path
        self.predictor = None
        self.predictions = {}
        self.actuals = {}
        self.modifications = []
        
    def load_model(self):
        """Load trained prediction model"""
        if self.model_path.exists():
            print(f"Loading model from {self.model_path}")
            self.predictor = ResourcePredictor.load(self.model_path)
            print(f"Model loaded. Available stages: {self.predictor.stages}")
        else:
            print(f"ERROR: Model not found at {self.model_path}")
            print("Train model first: python prediction/train_model.py")
            sys.exit(1)
    
    def phase1_predict_before_job(self, design_features: Dict, tool_config: Dict):
        """
        PHASE 1: Predict resources BEFORE job starts
        
        This is what happens when user submits a job to SLURM
        """
        print("\n" + "="*70)
        print("PHASE 1: PRE-JOB PREDICTION")
        print("="*70)
        
        print("\nDesign Features:")
        for key, value in design_features.items():
            print(f"  {key}: {value}")
        
        print("\nTool Configuration:")
        for key, value in tool_config.items():
            print(f"  {key}: {value}")
        
        print("\n" + "-"*70)
        print("Predicting resources for all stages...")
        print("-"*70)
        
        # Predict for each stage
        for stage in self.predictor.stages:
            pred = self.predictor.predict(stage, design_features, tool_config)
            self.predictions[stage] = pred
            
            print(f"\n{stage.upper()}:")
            print(f"  Predicted CPU cores:  {pred['cpu_cores']:.1f}")
            print(f"  Predicted Memory:     {pred['memory_gb']:.1f} GB")
            print(f"  Predicted Duration:   {pred['duration_sec']:.0f} sec ({pred['duration_sec']/60:.1f} min)")
        
        # Calculate total job requirements
        total_duration = sum(p['duration_sec'] for p in self.predictions.values())
        max_memory = max(p['memory_gb'] for p in self.predictions.values())
        max_cpu = max(p['cpu_cores'] for p in self.predictions.values())
        
        print("\n" + "-"*70)
        print("TOTAL JOB PREDICTIONS:")
        print("-"*70)
        print(f"  Total Duration:  {total_duration:.0f} sec ({total_duration/60:.1f} min)")
        print(f"  Peak Memory:     {max_memory:.1f} GB")
        print(f"  Peak CPU Cores:  {max_cpu:.1f}")
        
        return {
            'total_duration_sec': total_duration,
            'peak_memory_gb': max_memory,
            'peak_cpu_cores': max_cpu,
            'stage_predictions': self.predictions
        }
    
    def phase2_generate_slurm_job(self, predictions: Dict, design_name: str):
        """
        PHASE 2: Generate SLURM job script with predicted resources
        
        This creates the initial SLURM job submission
        """
        print("\n" + "="*70)
        print("PHASE 2: GENERATE SLURM JOB SCRIPT")
        print("="*70)
        
        # Add 20% buffer to predictions
        buffer = 1.2
        cpu_cores = int(predictions['peak_cpu_cores'] * buffer)
        memory_gb = int(predictions['peak_memory_gb'] * buffer)
        time_hours = int((predictions['total_duration_sec'] * buffer) / 3600) + 1
        
        slurm_script = f"""#!/bin/bash
#SBATCH --job-name={design_name}
#SBATCH --nodes=1
#SBATCH --ntasks={cpu_cores}
#SBATCH --mem={memory_gb}G
#SBATCH --time={time_hours}:00:00
#SBATCH --output=logs/{design_name}_%j.out
#SBATCH --error=logs/{design_name}_%j.err

# SPANK plugin will monitor this job
# Predictions stored for comparison

echo "Job started: $(date)"
echo "Predicted resources: {cpu_cores} cores, {memory_gb}GB, {time_hours}h"

# Run OpenROAD flow
cd /OpenROAD-flow-scripts/flow
make DESIGN_CONFIG=designs/asap7/{design_name}/config.mk

echo "Job completed: $(date)"
"""
        
        print("\nGenerated SLURM Script:")
        print("-"*70)
        print(slurm_script)
        print("-"*70)
        
        print(f"\nInitial Resource Allocation:")
        print(f"  CPU Cores: {cpu_cores} (predicted {predictions['peak_cpu_cores']:.1f} + 20% buffer)")
        print(f"  Memory:    {memory_gb}GB (predicted {predictions['peak_memory_gb']:.1f}GB + 20% buffer)")
        print(f"  Time:      {time_hours}h (predicted {predictions['total_duration_sec']/3600:.1f}h + 20% buffer)")
        
        return slurm_script
    
    def phase3_monitor_stage(self, stage_name: str, actual_metrics: Dict):
        """
        PHASE 3: Monitor actual resource usage during job execution
        
        This is what SPANK plugin does in real-time
        """
        print("\n" + "="*70)
        print(f"PHASE 3: MONITORING STAGE - {stage_name.upper()}")
        print("="*70)
        
        self.actuals[stage_name] = actual_metrics
        
        predicted = self.predictions.get(stage_name, {})
        
        print(f"\n{stage_name.upper()} - Prediction vs Actual:")
        print("-"*70)
        
        # CPU comparison
        pred_cpu = predicted.get('cpu_cores', 0)
        actual_cpu = actual_metrics.get('cpu_cores', 0)
        cpu_error = abs(pred_cpu - actual_cpu) / pred_cpu * 100 if pred_cpu > 0 else 0
        print(f"CPU Cores:")
        print(f"  Predicted: {pred_cpu:.1f}")
        print(f"  Actual:    {actual_cpu:.1f}")
        print(f"  Error:     {cpu_error:.1f}%")
        
        # Memory comparison
        pred_mem = predicted.get('memory_gb', 0)
        actual_mem = actual_metrics.get('memory_gb', 0)
        mem_error = abs(pred_mem - actual_mem) / pred_mem * 100 if pred_mem > 0 else 0
        print(f"\nMemory:")
        print(f"  Predicted: {pred_mem:.1f} GB")
        print(f"  Actual:    {actual_mem:.1f} GB")
        print(f"  Error:     {mem_error:.1f}%")
        
        # Duration comparison
        pred_dur = predicted.get('duration_sec', 0)
        actual_dur = actual_metrics.get('duration_sec', 0)
        dur_error = abs(pred_dur - actual_dur) / pred_dur * 100 if pred_dur > 0 else 0
        print(f"\nDuration:")
        print(f"  Predicted: {pred_dur:.0f} sec ({pred_dur/60:.1f} min)")
        print(f"  Actual:    {actual_dur:.0f} sec ({actual_dur/60:.1f} min)")
        print(f"  Error:     {dur_error:.1f}%")
        
        # Determine if adjustment needed
        needs_adjustment = mem_error > 20 or cpu_error > 20
        
        if needs_adjustment:
            print(f"\n⚠️  ADJUSTMENT NEEDED: Error > 20%")
        else:
            print(f"\n✓ Prediction accurate (error < 20%)")
        
        return {
            'stage': stage_name,
            'cpu_error_pct': cpu_error,
            'memory_error_pct': mem_error,
            'duration_error_pct': dur_error,
            'needs_adjustment': needs_adjustment
        }
    
    def phase4_adjust_slurm_job(self, stage_name: str, remaining_stages: List[str], 
                                 comparison: Dict):
        """
        PHASE 4: Adjust SLURM job resources for remaining stages
        
        This is the dynamic resource allocation based on actual vs predicted
        """
        print("\n" + "="*70)
        print("PHASE 4: DYNAMIC RESOURCE ADJUSTMENT")
        print("="*70)
        
        if not comparison['needs_adjustment']:
            print("\nNo adjustment needed - predictions are accurate")
            return None
        
        print(f"\nCompleted stage: {stage_name}")
        print(f"Remaining stages: {', '.join(remaining_stages)}")
        
        # Calculate adjustment factor based on actual vs predicted
        actual = self.actuals[stage_name]
        predicted = self.predictions[stage_name]
        
        cpu_factor = actual['cpu_cores'] / predicted['cpu_cores'] if predicted['cpu_cores'] > 0 else 1.0
        mem_factor = actual['memory_gb'] / predicted['memory_gb'] if predicted['memory_gb'] > 0 else 1.0
        
        print(f"\nAdjustment factors based on {stage_name}:")
        print(f"  CPU factor:    {cpu_factor:.2f}x")
        print(f"  Memory factor: {mem_factor:.2f}x")
        
        # Adjust predictions for remaining stages
        print(f"\nAdjusted predictions for remaining stages:")
        print("-"*70)
        
        adjustments = {}
        for remaining_stage in remaining_stages:
            orig_pred = self.predictions[remaining_stage]
            adjusted = {
                'cpu_cores': orig_pred['cpu_cores'] * cpu_factor,
                'memory_gb': orig_pred['memory_gb'] * mem_factor,
                'duration_sec': orig_pred['duration_sec']  # Keep duration same for now
            }
            adjustments[remaining_stage] = adjusted
            
            print(f"\n{remaining_stage.upper()}:")
            print(f"  CPU:    {orig_pred['cpu_cores']:.1f} → {adjusted['cpu_cores']:.1f}")
            print(f"  Memory: {orig_pred['memory_gb']:.1f}GB → {adjusted['memory_gb']:.1f}GB")
        
        # Calculate new resource requirements
        new_max_cpu = max(a['cpu_cores'] for a in adjustments.values())
        new_max_mem = max(a['memory_gb'] for a in adjustments.values())
        
        print(f"\n" + "-"*70)
        print("NEW RESOURCE ALLOCATION:")
        print("-"*70)
        print(f"  CPU Cores: {int(new_max_cpu * 1.1)} (adjusted + 10% buffer)")
        print(f"  Memory:    {int(new_max_mem * 1.1)}GB (adjusted + 10% buffer)")
        
        # Generate SLURM modification command
        slurm_mod_cmd = f"""
# Modify running SLURM job resources
scontrol update JobId=$SLURM_JOB_ID NumCPUs={int(new_max_cpu * 1.1)} MinMemoryNode={int(new_max_mem * 1.1)}G

echo "Resources adjusted after {stage_name} stage"
echo "New allocation: {int(new_max_cpu * 1.1)} cores, {int(new_max_mem * 1.1)}GB"
"""
        
        print(f"\nSLURM Modification Command:")
        print(slurm_mod_cmd)
        
        modification = {
            'after_stage': stage_name,
            'adjustment_factors': {'cpu': cpu_factor, 'memory': mem_factor},
            'new_allocation': {
                'cpu_cores': int(new_max_cpu * 1.1),
                'memory_gb': int(new_max_mem * 1.1)
            },
            'slurm_command': slurm_mod_cmd
        }
        
        self.modifications.append(modification)
        return modification
    
    def phase5_final_report(self):
        """
        PHASE 5: Generate final report comparing all predictions vs actuals
        """
        print("\n" + "="*70)
        print("PHASE 5: FINAL REPORT")
        print("="*70)
        
        print("\nPrediction Accuracy Summary:")
        print("-"*70)
        
        total_errors = {'cpu': [], 'memory': [], 'duration': []}
        
        for stage in self.predictions.keys():
            if stage in self.actuals:
                pred = self.predictions[stage]
                actual = self.actuals[stage]
                
                cpu_err = abs(pred['cpu_cores'] - actual['cpu_cores']) / pred['cpu_cores'] * 100
                mem_err = abs(pred['memory_gb'] - actual['memory_gb']) / pred['memory_gb'] * 100
                dur_err = abs(pred['duration_sec'] - actual['duration_sec']) / pred['duration_sec'] * 100
                
                total_errors['cpu'].append(cpu_err)
                total_errors['memory'].append(mem_err)
                total_errors['duration'].append(dur_err)
                
                print(f"\n{stage.upper()}:")
                print(f"  CPU Error:      {cpu_err:.1f}%")
                print(f"  Memory Error:   {mem_err:.1f}%")
                print(f"  Duration Error: {dur_err:.1f}%")
        
        # Overall accuracy
        print(f"\n" + "-"*70)
        print("OVERALL ACCURACY:")
        print("-"*70)
        if total_errors['cpu']:
            print(f"  Average CPU Error:      {sum(total_errors['cpu'])/len(total_errors['cpu']):.1f}%")
            print(f"  Average Memory Error:   {sum(total_errors['memory'])/len(total_errors['memory']):.1f}%")
            print(f"  Average Duration Error: {sum(total_errors['duration'])/len(total_errors['duration']):.1f}%")
        
        # Modifications made
        print(f"\n" + "-"*70)
        print(f"DYNAMIC ADJUSTMENTS MADE: {len(self.modifications)}")
        print("-"*70)
        for i, mod in enumerate(self.modifications, 1):
            print(f"\nAdjustment {i}:")
            print(f"  After stage: {mod['after_stage']}")
            print(f"  CPU factor:  {mod['adjustment_factors']['cpu']:.2f}x")
            print(f"  Memory factor: {mod['adjustment_factors']['memory']:.2f}x")
            print(f"  New allocation: {mod['new_allocation']['cpu_cores']} cores, {mod['new_allocation']['memory_gb']}GB")
        
        # Save report
        report = {
            'timestamp': datetime.now().isoformat(),
            'predictions': self.predictions,
            'actuals': self.actuals,
            'modifications': self.modifications,
            'accuracy': {
                'cpu_error_avg': sum(total_errors['cpu'])/len(total_errors['cpu']) if total_errors['cpu'] else 0,
                'memory_error_avg': sum(total_errors['memory'])/len(total_errors['memory']) if total_errors['memory'] else 0,
                'duration_error_avg': sum(total_errors['duration'])/len(total_errors['duration']) if total_errors['duration'] else 0
            }
        }
        
        report_file = Path('data/prediction_flow_report.json')
        report_file.parent.mkdir(parents=True, exist_ok=True)
        with open(report_file, 'w') as f:
            json.dump(report, f, indent=2)
        
        print(f"\n✓ Report saved to: {report_file}")


def main():
    """Run complete end-to-end prediction flow test"""
    
    print("="*70)
    print("END-TO-END PREDICTION FLOW TEST")
    print("="*70)
    print("\nThis demonstrates:")
    print("1. Pre-job prediction based on design features")
    print("2. SLURM job generation with predicted resources")
    print("3. Real-time monitoring during execution")
    print("4. Dynamic resource adjustment")
    print("5. Final accuracy report")
    
    # Initialize
    model_path = Path('prediction/trained_model.pkl')
    flow = PredictionFlowTest(model_path)
    flow.load_model()
    
    # Test design: Medium-sized AES core
    design_features = {
        'cell_count': 25000,
        'net_count': 22500,
        'die_area_um2': 5000000,
        'utilization_target': 0.65,
        'aspect_ratio': 1.0,
        'clock_freq_mhz': 250,
        'clock_domains': 1,
        'technology_node_nm': 45,
        'metal_layers': 8,
        'clock_gating_enabled': True,
        'power_gating_enabled': False,
        'hierarchy_depth': 4,
        'macro_count': 2
    }
    
    tool_config = {
        'tool': 'openroad',
        'threads': 8,
        'version': '2.0'
    }
    
    # PHASE 1: Predict before job
    predictions = flow.phase1_predict_before_job(design_features, tool_config)
    
    # PHASE 2: Generate SLURM job
    slurm_script = flow.phase2_generate_slurm_job(predictions, 'aes_test')
    
    # PHASE 3 & 4: Simulate execution with monitoring and adjustment
    # In real system, this would be done by SPANK plugin
    
    print("\n" + "="*70)
    print("SIMULATING JOB EXECUTION...")
    print("="*70)
    print("(In production, SPANK plugin would monitor real execution)")
    
    # Simulate synthesis stage (actual slightly higher than predicted)
    synthesis_actual = {
        'cpu_cores': predictions['stage_predictions']['synthesis']['cpu_cores'] * 1.1,
        'memory_gb': predictions['stage_predictions']['synthesis']['memory_gb'] * 1.15,
        'duration_sec': predictions['stage_predictions']['synthesis']['duration_sec'] * 1.05
    }
    comparison = flow.phase3_monitor_stage('synthesis', synthesis_actual)
    
    # Adjust if needed
    remaining = ['placement', 'routing']  # Simplified
    if comparison['needs_adjustment']:
        flow.phase4_adjust_slurm_job('synthesis', remaining, comparison)
    
    # Simulate placement stage with adjusted resources
    placement_actual = {
        'cpu_cores': predictions['stage_predictions']['placement']['cpu_cores'] * 1.08,
        'memory_gb': predictions['stage_predictions']['placement']['memory_gb'] * 1.12,
        'duration_sec': predictions['stage_predictions']['placement']['duration_sec'] * 0.98
    }
    comparison = flow.phase3_monitor_stage('placement', placement_actual)
    
    # PHASE 5: Final report
    flow.phase5_final_report()
    
    print("\n" + "="*70)
    print("✓ END-TO-END FLOW COMPLETE")
    print("="*70)


if __name__ == "__main__":
    main()
