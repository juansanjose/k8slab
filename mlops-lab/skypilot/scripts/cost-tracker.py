#!/usr/bin/env python3
"""
SkyPilot Cost Tracker
Monitors spending across Vast.ai GPU instances
"""

import json
import sys
from datetime import datetime
from pathlib import Path

COST_LOG = Path.home() / ".skypilot_costs.json"

def load_costs():
    if COST_LOG.exists():
        with open(COST_LOG) as f:
            return json.load(f)
    return {"runs": [], "total_spent": 0.0}

def save_costs(data):
    with open(COST_LOG, "w") as f:
        json.dump(data, f, indent=2)

def log_run(cluster_name, gpu_type, hourly_rate, duration_hours):
    costs = load_costs()
    run_cost = hourly_rate * duration_hours
    
    costs["runs"].append({
        "cluster": cluster_name,
        "gpu": gpu_type,
        "hourly_rate": hourly_rate,
        "duration_hours": round(duration_hours, 2),
        "cost": round(run_cost, 4),
        "timestamp": datetime.now().isoformat()
    })
    
    costs["total_spent"] = round(costs["total_spent"] + run_cost, 4)
    save_costs(costs)
    
    print(f"Logged: {cluster_name} | {gpu_type} | ${hourly_rate}/hr | {duration_hours:.2f}h | ${run_cost:.4f}")
    print(f"Total spent: ${costs['total_spent']:.4f}")

def show_summary():
    costs = load_costs()
    
    if not costs["runs"]:
        print("No cost data yet. Run training jobs to track costs.")
        return
    
    print("=" * 80)
    print(f"{'Cluster':<20} {'GPU':<15} {'Rate':<10} {'Hours':<10} {'Cost':<10} {'Date'}")
    print("=" * 80)
    
    for run in costs["runs"][-10:]:  # Show last 10
        date = run["timestamp"][:10]
        print(f"{run['cluster']:<20} {run['gpu']:<15} ${run['hourly_rate']:<9.4f} "
              f"{run['duration_hours']:<10.2f} ${run['cost']:<10.4f} {date}")
    
    print("=" * 80)
    print(f"Total Spent: ${costs['total_spent']:.4f}")
    print(f"Total Runs: {len(costs['runs'])}")

if __name__ == "__main__":
    if len(sys.argv) < 2:
        show_summary()
    elif sys.argv[1] == "log" and len(sys.argv) == 6:
        log_run(sys.argv[2], sys.argv[3], float(sys.argv[4]), float(sys.argv[5]))
    else:
        print("Usage:")
        print("  cost-tracker.py                  # Show summary")
        print("  cost-tracker.py log NAME GPU RATE HOURS  # Log a run")
        print("")
        print("Example:")
        print("  cost-tracker.py log llm-train RTX4090 0.35 1.5")