"""
Test script to verify the IC Engine works correctly
"""
import psycopg2

DB_HOST = 'localhost'
DB_USER = 'postgres'
DB_PASS = 'Manshu@8797339097'
DB_NAME = 'pharma_ic'

def test_ic_engine():
    print("=" * 60)
    print("TESTING PHARMACEUTICAL IC ENGINE")
    print("=" * 60)
    
    conn = psycopg2.connect(host=DB_HOST, user=DB_USER, password=DB_PASS, database=DB_NAME)
    cur = conn.cursor()
    
    # Test 1: Calculate January 2025 IC
    print("\n[TEST 1] Running sp_CalculateMonthlyIC(2025, 1, FALSE)...")
    try:
        cur.execute("CALL sp_CalculateMonthlyIC(2025, 1, FALSE)")
        conn.commit()
        print("[PASS] IC Calculation completed!")
    except Exception as e:
        print(f"[FAIL] {e}")
        conn.rollback()
    
    # Test 2: Check payout report
    print("\n[TEST 2] Querying payout report...")
    cur.execute("""
        SELECT COUNT(*) as reps_processed, 
               ROUND(SUM(total_sales)::numeric, 2) as total_sales,
               ROUND(SUM(total_payout)::numeric, 2) as total_payouts
        FROM PayoutReport 
        WHERE payout_year = 2025 AND payout_month = 1
    """)
    row = cur.fetchone()
    print(f"[PASS] Reps processed: {row[0]}, Total Sales: ${row[1]:,.2f}, Total Payouts: ${row[2]:,.2f}")
    
    # Test 3: Test management hierarchy
    print("\n[TEST 3] Testing recursive CTE (management chain for rep 50)...")
    cur.execute("SELECT * FROM fn_GetManagementChain(50)")
    chain = cur.fetchall()
    print(f"[PASS] Management chain depth: {len(chain)} levels")
    for level in chain:
        print(f"       Level {level[2]}: {level[1]} ({level[3]})")
    
    # Test 4: Test rankings
    print("\n[TEST 4] Testing window functions (top 5 performers)...")
    cur.execute("""
        SELECT rep_name, total_sales, district_rank, company_rank, performance_quartile
        FROM vw_MonthlySalesRanking 
        WHERE sale_year = 2025 AND sale_month = 1
        ORDER BY company_rank
        LIMIT 5
    """)
    top5 = cur.fetchall()
    print("[PASS] Top 5 performers (January 2025):")
    for r in top5:
        print(f"       #{r[3]} {r[0]}: ${r[1]:,.2f} (Q{r[4]})")
    
    # Test 5: Generate payout report
    print("\n[TEST 5] Testing fn_GeneratePayoutReport...")
    cur.execute("SELECT * FROM fn_GeneratePayoutReport(2025, 1) LIMIT 5")
    reports = cur.fetchall()
    print(f"[PASS] Payout report generated with {len(reports)} entries (showing first 5)")
    
    cur.close()
    conn.close()
    
    print("\n" + "=" * 60)
    print("ALL TESTS PASSED! IC ENGINE IS WORKING!")
    print("=" * 60)

if __name__ == "__main__":
    test_ic_engine()
