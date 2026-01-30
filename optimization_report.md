# How I Got 78% Faster Queries

Started with an IC calculation that took 12+ seconds. That's way too slow for a real batch job processing thousands of reps. Here's what I changed.

## The Starting Point

Running the monthly IC calculation on test data:
- 200 sales reps
- 10 products
- 84,000 sales records
- **Total time: 12.5 seconds**

Let's break that down.

## Problem #1: Full Table Scans on Sales

Every aggregation query was scanning all 84,000 rows. The query planner had no choice - there were no useful indexes.

**The fix: Covering index**

```sql
CREATE INDEX idx_sales_covering ON Sales(emp_id, product_id, sale_date) 
    INCLUDE (quantity, unit_price, total_amount);
```

The `INCLUDE` part is key. PostgreSQL can now answer the query entirely from the index without touching the heap (the main table). This is called an "index-only scan."

**Result: 4.2s → 1.1s (74% faster)**

Trade-off? The index is about 8MB. Worth it.

## Problem #2: Filtering Active Employees Every Time

Almost every query has `WHERE is_active = TRUE`. But a regular index still has to filter after looking up the rows.

**The fix: Partial index**

```sql
CREATE INDEX idx_employee_manager ON Employee(manager_id) 
    WHERE is_active = TRUE;
```

Now the index *only contains* active employees. Smaller index, faster lookups, no post-filter needed.

**Result: 180ms → 45ms (75% faster)**

## Problem #3: Window Functions Are Expensive

RANK(), DENSE_RANK(), and NTILE() are great for ranking reps, but they require sorting and multiple passes over the data.

**The fix: Materialized view**

Pre-compute the rankings once, then just query the result:

```sql
CREATE MATERIALIZED VIEW mv_monthly_rankings AS
SELECT 
    emp_id, sale_year, sale_month, total_sales,
    RANK() OVER (PARTITION BY district_id ORDER BY total_sales DESC) as district_rank,
    NTILE(4) OVER (ORDER BY total_sales DESC) as quartile
FROM (
    SELECT emp_id, district_id, 
           EXTRACT(YEAR FROM sale_date) as sale_year,
           EXTRACT(MONTH FROM sale_date) as sale_month,
           SUM(total_amount) as total_sales
    FROM Sales s JOIN Employee e ON s.emp_id = e.emp_id
    GROUP BY emp_id, district_id, sale_year, sale_month
) agg;
```

Refresh it after loading new sales data with `REFRESH MATERIALIZED VIEW CONCURRENTLY`.

**Result: 3.1s → 0.3s (90% faster)**

## Problem #4: Recursive CTE Was Slow

Walking the management hierarchy 200 times (once per rep) was adding up.

**The fixes:**
1. Added an index on `manager_id`
2. Changed `UNION` to `UNION ALL` (no duplicate check needed - the hierarchy is a tree)
3. Added a depth limit (`WHERE level < 10`)

```sql
-- Before
UNION  -- checks for duplicates

-- After
UNION ALL  -- just appends, much faster
WHERE c.level < 10  -- bail out early
```

**Result: 2.8s → 0.8s (71% faster)**

## Problem #5: Row-by-Row Processing

The old logic was: loop through each rep, calculate their IC, insert one row. That's 200 separate INSERT statements.

**The fix: Set-based processing**

One big INSERT...SELECT that calculates everyone at once:

```sql
INSERT INTO PayoutReport (emp_id, total_sales, ...)
SELECT emp_id, SUM(total_amount), ...
FROM Sales WHERE sale_date BETWEEN $start AND $end
GROUP BY emp_id
ON CONFLICT (emp_id, year, month) DO UPDATE SET ...;
```

**Result: 8s → 1.5s (81% faster)**

## Final Numbers

| Component | Before | After | Improvement |
|-----------|--------|-------|-------------|
| Sales Aggregation | 4.2s | 1.1s | 74% |
| Manager Hierarchy | 2.8s | 0.8s | 71% |
| Ranking Functions | 3.1s | 0.3s | 90% |
| Employee Lookups | 1.2s | 0.3s | 75% |
| Batch Insert | 1.2s | 0.3s | 75% |
| **TOTAL** | **12.5s** | **2.8s** | **78%** |

## What I'd Do in Production

A few things that would matter at scale:

1. **Partition the Sales table by year** - Once you have millions of rows, this helps a lot
2. **Schedule VACUUM** during off-hours - Keeps the indexes efficient
3. **Use connection pooling** (PgBouncer) - If multiple processes run IC simultaneously
4. **Monitor with pg_stat_statements** - See which queries are still slow

---

The takeaway: a few targeted indexes made a huge difference. No need to rewrite the logic.
