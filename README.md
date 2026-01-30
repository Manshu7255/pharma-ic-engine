# Pharmaceutical IC Engine

A backend system I built to calculate monthly sales commissions for pharma reps. If you've ever wondered how companies like ZS Associates handle billions in incentive payouts - this is that kind of system.

## What's This About?

Pharma sales reps earn commissions based on hitting quotas. Sounds simple, but it gets complicated fast:
- Reps report to District Managers, who report to Regional Directors, who report to VPs
- Everyone gets a cut of their team's performance
- Historical data matters (a rep who switched territories mid-quarter still gets credit for old sales)
- Performance is ranked against peers for bonus tiers

This project tackles all of that with PostgreSQL.

## The Interesting SQL Stuff

**Recursive CTEs** - Climbing the org chart from any rep up to the VP:
```sql
WITH RECURSIVE ManagementChain AS (
    SELECT emp_id, manager_id, 1 as level FROM Employee WHERE emp_id = 50
    UNION ALL
    SELECT e.emp_id, e.manager_id, mc.level + 1
    FROM Employee e JOIN ManagementChain mc ON e.emp_id = mc.manager_id
)
SELECT * FROM ManagementChain;
```

**Window Functions** - Ranking reps within their district and company-wide:
```sql
RANK() OVER (PARTITION BY district_id ORDER BY total_sales DESC)
NTILE(4) OVER (ORDER BY total_sales DESC)  -- Top 25%, etc.
```

**SCD Type 2** - Tracking when reps change territories (yes, this comes up a lot in pharma)

## Getting Started

You'll need PostgreSQL 14+ and Python 3.8+.

```bash
# Install the Python PostgreSQL driver
pip install psycopg2-binary

# Generate test data (creates ~50k sales records)
python generate_data.py

# Set up the database
# (edit build_database.py first to add your postgres password)
python build_database.py

# Run the tests
python test_ic_engine.py
```

If everything works, you'll see something like:
```
✅ Reps Processed: 141
✅ Total Sales: $47.9M
✅ Total Payouts: $892K
```

## Project Files

| File | What It Does |
|------|--------------|
| `01_schema.sql` | All the tables, indexes, and views |
| `02_stored_procedures.sql` | The IC calculation engine |
| `generate_data.py` | Creates realistic test data |
| `build_database.py` | Sets everything up automatically |
| `er_diagram.md` | Visual breakdown of the schema |
| `optimization_report.md` | How I got 78% faster queries |

## Running IC Calculations

Once the database is set up:

```sql
-- Calculate January 2025 commissions
CALL sp_CalculateMonthlyIC(2025, 1, FALSE);

-- See the payout report
SELECT * FROM fn_GeneratePayoutReport(2025, 1);

-- Check who reports to manager #7
SELECT * FROM fn_GetAllReports(7);
```

## Performance Notes

Started with queries taking 12+ seconds. After adding:
- Covering indexes (no table lookups needed)
- Partial indexes (only index active employees)
- A materialized view for rankings

Got it down to under 3 seconds. Details in `optimization_report.md`.

## Why I Built This

Wanted to practice the kind of SQL that actually shows up in enterprise data work - not just basic JOINs, but the stuff you'd find in a real compensation system. The recursive CTEs and window functions were particularly fun to figure out.

---

Questions or suggestions? Feel free to open an issue.
