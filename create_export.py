"""
Combine all project files into a single export for GitHub
"""
import os

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
OUTPUT_FILE = os.path.join(SCRIPT_DIR, "FULL_PROJECT_EXPORT.txt")

# Files to include (in order)
FILES = [
    ("README.md", "Project Documentation"),
    ("01_schema.sql", "Database Schema"),
    ("02_stored_procedures.sql", "Stored Procedures"),
    ("generate_data.py", "Data Generator"),
    ("build_database.py", "Database Builder"),
    ("test_ic_engine.py", "Test Script"),
    ("er_diagram.md", "ER Diagram"),
    ("optimization_report.md", "Optimization Report"),
]

def main():
    output = []
    output.append("=" * 80)
    output.append("PHARMACEUTICAL IC ENGINE - COMPLETE PROJECT EXPORT")
    output.append("For GitHub Upload")
    output.append("=" * 80)
    output.append("")
    output.append("NOTE: Run 'python generate_data.py' to create 03_sample_data.sql")
    output.append("      (50,000+ lines of test data)")
    output.append("")
    
    for filename, description in FILES:
        filepath = os.path.join(SCRIPT_DIR, filename)
        if os.path.exists(filepath):
            output.append("=" * 80)
            output.append(f"FILE: {filename}")
            output.append(f"DESCRIPTION: {description}")
            output.append("=" * 80)
            output.append("")
            with open(filepath, 'r', encoding='utf-8') as f:
                output.append(f.read())
            output.append("")
            output.append("")
    
    with open(OUTPUT_FILE, 'w', encoding='utf-8') as f:
        f.write('\n'.join(output))
    
    print(f"Created: {OUTPUT_FILE}")
    print(f"Total size: {os.path.getsize(OUTPUT_FILE):,} bytes")

if __name__ == "__main__":
    main()
