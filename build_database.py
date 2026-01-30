"""
Build script for Pharmaceutical IC Engine Database
Creates database, loads schema, stored procedures, and sample data
"""

import psycopg2
from psycopg2.extensions import ISOLATION_LEVEL_AUTOCOMMIT
import os

# Configuration
DB_HOST = 'localhost'
DB_USER = 'postgres'
DB_PASS = 'Manshu@8797339097'
DB_NAME = 'pharma_ic'

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))

def create_database():
    """Create the pharma_ic database if it doesn't exist"""
    print("=" * 60)
    print("PHARMACEUTICAL IC ENGINE - DATABASE BUILDER")
    print("=" * 60)
    
    conn = psycopg2.connect(host=DB_HOST, user=DB_USER, password=DB_PASS)
    conn.set_isolation_level(ISOLATION_LEVEL_AUTOCOMMIT)
    cur = conn.cursor()
    
    # Check if database exists
    cur.execute("SELECT 1 FROM pg_database WHERE datname = %s", (DB_NAME,))
    exists = cur.fetchone()
    
    if exists:
        print(f"[INFO] Database '{DB_NAME}' already exists. Dropping and recreating...")
        cur.execute(f"DROP DATABASE {DB_NAME}")
    
    cur.execute(f"CREATE DATABASE {DB_NAME}")
    print(f"[OK] Database '{DB_NAME}' created successfully!")
    
    cur.close()
    conn.close()

def run_sql_file(filename):
    """Execute a SQL file against the pharma_ic database"""
    filepath = os.path.join(SCRIPT_DIR, filename)
    
    if not os.path.exists(filepath):
        print(f"[ERROR] File not found: {filepath}")
        return False
    
    print(f"\n[RUNNING] {filename}...")
    
    conn = psycopg2.connect(host=DB_HOST, user=DB_USER, password=DB_PASS, database=DB_NAME)
    conn.set_isolation_level(ISOLATION_LEVEL_AUTOCOMMIT)
    cur = conn.cursor()
    
    with open(filepath, 'r', encoding='utf-8') as f:
        sql = f.read()
    
    try:
        cur.execute(sql)
        print(f"[OK] {filename} executed successfully!")
        success = True
    except Exception as e:
        print(f"[ERROR] {filename}: {e}")
        success = False
    
    cur.close()
    conn.close()
    return success

def verify_setup():
    """Verify the database was set up correctly"""
    print("\n" + "=" * 60)
    print("VERIFICATION")
    print("=" * 60)
    
    conn = psycopg2.connect(host=DB_HOST, user=DB_USER, password=DB_PASS, database=DB_NAME)
    cur = conn.cursor()
    
    # Count tables
    cur.execute("""
        SELECT table_name FROM information_schema.tables 
        WHERE table_schema = 'public' AND table_type = 'BASE TABLE'
    """)
    tables = cur.fetchall()
    print(f"\n[OK] Tables created: {len(tables)}")
    for t in tables:
        cur.execute(f"SELECT COUNT(*) FROM {t[0]}")
        count = cur.fetchone()[0]
        print(f"     - {t[0]}: {count} rows")
    
    # Count functions
    cur.execute("""
        SELECT routine_name FROM information_schema.routines 
        WHERE routine_schema = 'public'
    """)
    funcs = cur.fetchall()
    print(f"\n[OK] Functions/Procedures created: {len(funcs)}")
    
    cur.close()
    conn.close()
    
    print("\n" + "=" * 60)
    print("DATABASE BUILD COMPLETE!")
    print("=" * 60)
    print("\nTo test the IC Engine, run:")
    print("  CALL sp_CalculateMonthlyIC(2025, 1, FALSE);")
    print("  SELECT * FROM fn_GeneratePayoutReport(2025, 1);")

def main():
    try:
        # Step 1: Create database
        create_database()
        
        # Step 2: Run schema
        if not run_sql_file('01_schema.sql'):
            return
        
        # Step 3: Run stored procedures
        if not run_sql_file('02_stored_procedures.sql'):
            return
        
        # Step 4: Load sample data
        if not run_sql_file('03_sample_data.sql'):
            return
        
        # Step 5: Verify
        verify_setup()
        
    except Exception as e:
        print(f"\n[FATAL ERROR] {e}")
        print("\nMake sure PostgreSQL is running and credentials are correct.")

if __name__ == "__main__":
    main()
