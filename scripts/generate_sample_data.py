#!/usr/bin/env python3
"""
Generate sample data for dashboard demonstration
Creates realistic job metrics with requested, actual, and predicted resources
"""

import sqlite3
import random
from datetime import datetime, timedelta
import json

def generate_sample_data(db_path='hpc_metrics.db', num_jobs=50):
    """Generate sample job data for dashboard"""
    
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()
    
    # Create tables if they don't exist
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS job_metrics (
            job_id INTEGER PRIMARY KEY AUTOINCREMENT,
            design_name TEXT NOT NULL,
            num_gates INTEGER,
            num_nets INTEGER,
            requested_cpu REAL,
            requested_memory_mb REAL,
            cpu_percent REAL,
            memory_mb REAL,
            predicted_cpu REAL,
            predicted_memory_mb REAL,
            runtime_seconds REAL,
            status TEXT DEFAULT 'completed',
            timestamp DATETIME DEFAULT CURRENT_TIMESTAMP
        )
    ''')
    
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS spank_metrics (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            job_id INTEGER,
            timestamp DATETIME,
            cpu_percent REAL,
            memory_mb REAL,
            io_read_mb REAL,
            io_write_mb REAL,
            FOREIGN KEY (job_id) REFERENCES job_metrics(job_id)
        )
    ''')
    
    designs = [
        'aes_cipher', 'jpeg_encoder', 'fft_processor', 'usb_controller',
        'ethernet_mac', 'dma_engine', 'cache_controller', 'uart_transceiver',
        'spi_master', 'i2c_controller', 'pcie_endpoint', 'ddr_controller'
    ]
    
    print(f"Generating {num_jobs} sample jobs...")
    
    for i in range(num_jobs):
        # Design attributes
        design_name = random.choice(designs)
        num_gates = random.randint(1000, 20000)
        num_nets = int(num_gates * random.uniform(0.8, 1.2))
        
        # Typical over-allocation (users request 2x what they need)
        base_cpu = 50 + (num_gates / 100)
        base_memory = 2048 + (num_gates * 0.5)
        
        requested_cpu = base_cpu * random.uniform(1.8, 2.5)  # Over-allocated
        requested_memory_mb = base_memory * random.uniform(1.8, 2.5)
        
        # Actual usage (what SPANK measures)
        actual_cpu = base_cpu * random.uniform(0.8, 1.2)
        actual_memory = base_memory * random.uniform(0.8, 1.2)
        
        # ML prediction (optimized with 20% buffer)
        predicted_cpu = actual_cpu * 1.2
        predicted_memory_mb = actual_memory * 1.2
        
        # Runtime
        runtime_seconds = 60 + (num_gates / 10) + random.uniform(-30, 30)
        
        # Timestamp (spread over last 24 hours)
        timestamp = datetime.now() - timedelta(
            hours=random.uniform(0, 24),
            minutes=random.uniform(0, 60)
        )
        
        # Status
        status = random.choices(
            ['completed', 'running', 'failed'],
            weights=[0.90, 0.08, 0.02]
        )[0]
        
        # Insert job
        cursor.execute('''
            INSERT INTO job_metrics (
                design_name, num_gates, num_nets,
                requested_cpu, requested_memory_mb,
                cpu_percent, memory_mb,
                predicted_cpu, predicted_memory_mb,
                runtime_seconds, status, timestamp
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ''', (
            design_name, num_gates, num_nets,
            requested_cpu, requested_memory_mb,
            actual_cpu, actual_memory,
            predicted_cpu, predicted_memory_mb,
            runtime_seconds, status, timestamp
        ))
        
        job_id = cursor.lastrowid
        
        # Generate SPANK timeline (10 samples per job)
        if status in ['completed', 'running']:
            for j in range(10):
                spank_timestamp = timestamp + timedelta(seconds=j * (runtime_seconds / 10))
                
                # Simulate varying resource usage
                cpu_variation = actual_cpu * random.uniform(0.8, 1.2)
                mem_variation = actual_memory * random.uniform(0.9, 1.1)
                io_read = random.uniform(10, 500)
                io_write = random.uniform(5, 200)
                
                cursor.execute('''
                    INSERT INTO spank_metrics (
                        job_id, timestamp, cpu_percent, memory_mb,
                        io_read_mb, io_write_mb
                    ) VALUES (?, ?, ?, ?, ?, ?)
                ''', (
                    job_id, spank_timestamp, cpu_variation, mem_variation,
                    io_read, io_write
                ))
        
        if (i + 1) % 10 == 0:
            print(f"  Generated {i + 1}/{num_jobs} jobs...")
    
    conn.commit()
    
    # Print summary
    cursor.execute('SELECT COUNT(*) FROM job_metrics')
    total_jobs = cursor.fetchone()[0]
    
    cursor.execute('''
        SELECT 
            AVG(requested_cpu) as avg_req_cpu,
            AVG(cpu_percent) as avg_actual_cpu,
            AVG(predicted_cpu) as avg_pred_cpu,
            AVG(requested_memory_mb) as avg_req_mem,
            AVG(memory_mb) as avg_actual_mem,
            AVG(predicted_memory_mb) as avg_pred_mem
        FROM job_metrics
    ''')
    
    row = cursor.fetchone()
    
    print(f"\n✓ Sample data generated successfully!")
    print(f"\nSummary:")
    print(f"  Total Jobs: {total_jobs}")
    print(f"  CPU - Requested: {row[0]:.1f}%, Actual: {row[1]:.1f}%, Predicted: {row[2]:.1f}%")
    print(f"  Memory - Requested: {row[3]:.0f}MB, Actual: {row[4]:.0f}MB, Predicted: {row[5]:.0f}MB")
    print(f"  CPU Savings: {((row[0] - row[2]) / row[0] * 100):.1f}%")
    print(f"  Memory Savings: {((row[3] - row[5]) / row[3] * 100):.1f}%")
    
    # Calculate cost savings
    cost_per_cpu_hour = 0.0425  # c5.xlarge
    cost_per_gb_hour = 0.02125
    
    cursor.execute('SELECT SUM(runtime_seconds) FROM job_metrics')
    total_runtime = cursor.fetchone()[0]
    hours = total_runtime / 3600
    
    current_cost = (row[0] / 100) * cost_per_cpu_hour * hours
    optimized_cost = (row[2] / 100) * cost_per_cpu_hour * hours
    savings = current_cost - optimized_cost
    
    print(f"\nCost Analysis:")
    print(f"  Current Cost: ${current_cost:.2f}")
    print(f"  Optimized Cost: ${optimized_cost:.2f}")
    print(f"  Savings: ${savings:.2f} ({(savings/current_cost*100):.1f}%)")
    print(f"  Annual Projection: ${savings * 365:.2f}")
    
    conn.close()
    
    print(f"\n✓ Database ready at: {db_path}")
    print(f"✓ Start dashboard: python3 dashboard/app.py")
    print(f"✓ Access at: http://localhost:5000")

if __name__ == '__main__':
    import argparse
    
    parser = argparse.ArgumentParser(description='Generate sample data for dashboard')
    parser.add_argument('--db', default='hpc_metrics.db', help='Database path')
    parser.add_argument('--jobs', type=int, default=50, help='Number of jobs to generate')
    
    args = parser.parse_args()
    
    generate_sample_data(args.db, args.jobs)
