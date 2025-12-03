#!/usr/bin/env python3
"""
HPC Resource Optimization Dashboard
Real-time monitoring and visualization of resource allocation optimization
"""

from flask import Flask, render_template, jsonify
import sqlite3
import json
from datetime import datetime, timedelta
import os

app = Flask(__name__)

DB_PATH = os.environ.get('DB_PATH', '../hpc_metrics.db')

def get_db_connection():
    """Get database connection"""
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    return conn

@app.route('/')
def index():
    """Main dashboard page"""
    return render_template('dashboard.html')

@app.route('/api/jobs/recent')
def get_recent_jobs():
    """Get recent jobs with all resource data"""
    conn = get_db_connection()
    cursor = conn.cursor()
    
    # Get recent jobs with full details
    cursor.execute('''
        SELECT 
            job_id,
            design_name,
            num_gates,
            num_nets,
            requested_cpu,
            requested_memory_mb,
            cpu_percent as actual_cpu,
            memory_mb as actual_memory,
            predicted_cpu,
            predicted_memory_mb,
            runtime_seconds,
            timestamp,
            status
        FROM job_metrics
        ORDER BY timestamp DESC
        LIMIT 20
    ''')
    
    jobs = []
    for row in cursor.fetchall():
        job = dict(row)
        
        # Calculate savings
        if job['requested_cpu'] and job['predicted_cpu']:
            job['cpu_savings_percent'] = ((job['requested_cpu'] - job['predicted_cpu']) / job['requested_cpu']) * 100
        else:
            job['cpu_savings_percent'] = 0
            
        if job['requested_memory_mb'] and job['predicted_memory_mb']:
            job['memory_savings_percent'] = ((job['requested_memory_mb'] - job['predicted_memory_mb']) / job['requested_memory_mb']) * 100
        else:
            job['memory_savings_percent'] = 0
        
        jobs.append(job)
    
    conn.close()
    return jsonify(jobs)

@app.route('/api/stats/summary')
def get_summary_stats():
    """Get summary statistics"""
    conn = get_db_connection()
    cursor = conn.cursor()
    
    # Overall statistics
    cursor.execute('''
        SELECT 
            COUNT(*) as total_jobs,
            AVG(cpu_percent) as avg_cpu_actual,
            AVG(memory_mb) as avg_memory_actual,
            AVG(requested_cpu) as avg_cpu_requested,
            AVG(requested_memory_mb) as avg_memory_requested,
            AVG(predicted_cpu) as avg_cpu_predicted,
            AVG(predicted_memory_mb) as avg_memory_predicted,
            SUM(runtime_seconds) as total_runtime
        FROM job_metrics
        WHERE timestamp > datetime('now', '-24 hours')
    ''')
    
    row = cursor.fetchone()
    stats = dict(row)
    
    # Calculate savings
    if stats['avg_cpu_requested'] and stats['avg_cpu_predicted']:
        stats['cpu_savings_percent'] = ((stats['avg_cpu_requested'] - stats['avg_cpu_predicted']) / stats['avg_cpu_requested']) * 100
    else:
        stats['cpu_savings_percent'] = 0
        
    if stats['avg_memory_requested'] and stats['avg_memory_predicted']:
        stats['memory_savings_percent'] = ((stats['avg_memory_requested'] - stats['avg_memory_predicted']) / stats['avg_memory_requested']) * 100
    else:
        stats['memory_savings_percent'] = 0
    
    # Cost calculations (c5.xlarge: $0.17/hour, 4 vCPUs, 8GB RAM)
    cost_per_cpu_hour = 0.0425  # $0.17 / 4 cores
    cost_per_gb_hour = 0.02125  # $0.17 / 8 GB
    
    hours = stats['total_runtime'] / 3600 if stats['total_runtime'] else 0
    
    current_cost = (
        (stats['avg_cpu_requested'] / 100) * cost_per_cpu_hour * hours +
        (stats['avg_memory_requested'] / 1024) * cost_per_gb_hour * hours
    ) if stats['avg_cpu_requested'] else 0
    
    optimized_cost = (
        (stats['avg_cpu_predicted'] / 100) * cost_per_cpu_hour * hours +
        (stats['avg_memory_predicted'] / 1024) * cost_per_gb_hour * hours
    ) if stats['avg_cpu_predicted'] else 0
    
    stats['current_cost'] = current_cost
    stats['optimized_cost'] = optimized_cost
    stats['cost_savings'] = current_cost - optimized_cost
    stats['cost_savings_percent'] = ((current_cost - optimized_cost) / current_cost * 100) if current_cost > 0 else 0
    
    conn.close()
    return jsonify(stats)

@app.route('/api/jobs/<int:job_id>')
def get_job_detail(job_id):
    """Get detailed information for a specific job"""
    conn = get_db_connection()
    cursor = conn.cursor()
    
    cursor.execute('''
        SELECT *
        FROM job_metrics
        WHERE job_id = ?
    ''', (job_id,))
    
    row = cursor.fetchone()
    if row:
        job = dict(row)
        
        # Add SPANK monitoring data if available
        cursor.execute('''
            SELECT 
                timestamp,
                cpu_percent,
                memory_mb,
                io_read_mb,
                io_write_mb
            FROM spank_metrics
            WHERE job_id = ?
            ORDER BY timestamp
        ''', (job_id,))
        
        job['spank_timeline'] = [dict(r) for r in cursor.fetchall()]
        
        conn.close()
        return jsonify(job)
    
    conn.close()
    return jsonify({'error': 'Job not found'}), 404

@app.route('/api/timeline')
def get_timeline_data():
    """Get timeline data for resource usage over time"""
    conn = get_db_connection()
    cursor = conn.cursor()
    
    cursor.execute('''
        SELECT 
            datetime(timestamp) as time,
            AVG(cpu_percent) as avg_cpu,
            AVG(memory_mb) as avg_memory,
            AVG(requested_cpu) as avg_requested_cpu,
            AVG(requested_memory_mb) as avg_requested_memory,
            AVG(predicted_cpu) as avg_predicted_cpu,
            AVG(predicted_memory_mb) as avg_predicted_memory
        FROM job_metrics
        WHERE timestamp > datetime('now', '-24 hours')
        GROUP BY strftime('%Y-%m-%d %H', timestamp)
        ORDER BY time
    ''')
    
    timeline = [dict(row) for row in cursor.fetchall()]
    conn.close()
    return jsonify(timeline)

@app.route('/api/design/correlation')
def get_design_correlation():
    """Get correlation between design attributes and resource usage"""
    conn = get_db_connection()
    cursor = conn.cursor()
    
    cursor.execute('''
        SELECT 
            num_gates,
            num_nets,
            cpu_percent,
            memory_mb,
            runtime_seconds
        FROM job_metrics
        ORDER BY num_gates
    ''')
    
    data = [dict(row) for row in cursor.fetchall()]
    conn.close()
    return jsonify(data)

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000, debug=True)
