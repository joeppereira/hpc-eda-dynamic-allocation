#!/usr/bin/env python3
"""
Generate Data Flow Diagram for ML-Driven Resource Optimization
Exports to PNG for insertion into Word documents
"""

from diagrams import Diagram, Cluster, Edge
from diagrams.custom import Custom
from diagrams.onprem.client import User
from diagrams.onprem.compute import Server
from diagrams.programming.framework import Flask
from diagrams.onprem.database import PostgreSQL

def generate_dataflow_diagram():
    """Generate the 5-stage data flow diagram"""
    
    graph_attr = {
        "fontsize": "16",
        "bgcolor": "white",
        "pad": "0.5",
        "rankdir": "LR",  # Left to right
        "splines": "ortho",
    }
    
    node_attr = {
        "fontsize": "14",
        "width": "2.0",
        "height": "1.5",
    }
    
    with Diagram(
        "ML-Driven Resource Optimization Flow",
        filename="docs/diagrams/dataflow-diagram",
        direction="LR",
        show=False,
        graph_attr=graph_attr,
        node_attr=node_attr
    ):
        
        # Stage 1: SUBMIT
        with Cluster("1. SUBMIT"):
            user = User("User")
            sbatch = Server("sbatch")
            user >> sbatch
        
        # Stage 2: PREDICT
        with Cluster("2. PREDICT"):
            ml_api = Flask("ML API")
            history = PostgreSQL("history")
            ml_api >> Edge(style="dashed") >> history
        
        # Stage 3: ALLOCATE
        with Cluster("3. ALLOCATE"):
            slurm = Server("SLURM")
            schedule = Server("schedule")
            slurm >> schedule
        
        # Stage 4: EXECUTE
        with Cluster("4. EXECUTE"):
            monitor = Server("Monitor")
            actual = Server("actual")
            monitor >> actual
        
        # Stage 5: LEARN
        with Cluster("5. LEARN"):
            update_db = PostgreSQL("Update DB")
            retrain = Flask("retrain")
            update_db >> retrain
        
        # Main flow connections
        sbatch >> Edge(label="job", color="blue", style="bold") >> ml_api
        ml_api >> Edge(label="predict", color="blue", style="bold") >> slurm
        slurm >> Edge(label="dispatch", color="blue", style="bold") >> monitor
        monitor >> Edge(label="metrics", color="blue", style="bold") >> update_db
        
        # Feedback loop
        update_db >> Edge(label="continuous learning", color="green", style="dashed") >> ml_api
    
    print("✓ Data flow diagram generated: docs/diagrams/dataflow-diagram.png")
    print("✓ Ready for insertion into Word document")

if __name__ == "__main__":
    generate_dataflow_diagram()
