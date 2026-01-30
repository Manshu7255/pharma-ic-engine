-- ============================================================
-- PHARMACEUTICAL IC ENGINE - STORED PROCEDURES
-- Database: PostgreSQL
-- Description: Core calculation engine for commissions
-- ============================================================

-- ============================================================
-- FUNCTION 1: Get Employee's Full Management Chain (Recursive CTE)
-- ============================================================
CREATE OR REPLACE FUNCTION fn_GetManagementChain(p_emp_id INTEGER)
RETURNS TABLE (
    emp_id INTEGER,
    emp_name VARCHAR,
    role VARCHAR,
    level INTEGER,
    manager_id INTEGER
) AS $$
BEGIN
    RETURN QUERY
    WITH RECURSIVE ManagementChain AS (
        -- Base case: Start with the given employee
        SELECT 
            e.emp_id,
            (e.first_name || ' ' || e.last_name)::VARCHAR as emp_name,
            e.role::VARCHAR,
            1 as level,
            e.manager_id
        FROM Employee e
        WHERE e.emp_id = p_emp_id
        
        UNION ALL
        
        -- Recursive: Go up the chain
        SELECT 
            e.emp_id,
            (e.first_name || ' ' || e.last_name)::VARCHAR,
            e.role::VARCHAR,
            mc.level + 1,
            e.manager_id
        FROM Employee e
        INNER JOIN ManagementChain mc ON e.emp_id = mc.manager_id
    )
    SELECT * FROM ManagementChain ORDER BY level;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION fn_GetManagementChain IS 'Recursive CTE to traverse Rep → DM → RD → VP hierarchy';

-- ============================================================
-- FUNCTION 2: Get All Direct and Indirect Reports (Downward)
-- ============================================================
CREATE OR REPLACE FUNCTION fn_GetAllReports(p_manager_id INTEGER)
RETURNS TABLE (
    emp_id INTEGER,
    emp_name VARCHAR,
    role VARCHAR,
    level INTEGER,
    direct_manager_id INTEGER
) AS $$
BEGIN
    RETURN QUERY
    WITH RECURSIVE TeamHierarchy AS (
        -- Base case: Direct reports
        SELECT 
            e.emp_id,
            (e.first_name || ' ' || e.last_name)::VARCHAR as emp_name,
            e.role::VARCHAR,
            1 as level,
            e.manager_id as direct_manager_id
        FROM Employee e
        WHERE e.manager_id = p_manager_id AND e.is_active = TRUE
        
        UNION ALL
        
        -- Recursive: Indirect reports
        SELECT 
            e.emp_id,
            (e.first_name || ' ' || e.last_name)::VARCHAR,
            e.role::VARCHAR,
            th.level + 1,
            e.manager_id
        FROM Employee e
        INNER JOIN TeamHierarchy th ON e.manager_id = th.emp_id
        WHERE e.is_active = TRUE
    )
    SELECT * FROM TeamHierarchy ORDER BY level, emp_name;
END;
$$ LANGUAGE plpgsql;

-- ============================================================
-- FUNCTION 3: Calculate Attainment Percentage
-- ============================================================
CREATE OR REPLACE FUNCTION fn_CalcAttainment(
    p_actual DECIMAL,
    p_target DECIMAL
) RETURNS DECIMAL AS $$
BEGIN
    IF p_target IS NULL OR p_target = 0 THEN
        RETURN 0;
    END IF;
    RETURN ROUND(p_actual / p_target, 4);
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- ============================================================
-- FUNCTION 4: Get Commission Rate from Tier
-- ============================================================
CREATE OR REPLACE FUNCTION fn_GetCommissionRate(p_attainment DECIMAL)
RETURNS DECIMAL AS $$
DECLARE
    v_rate DECIMAL;
BEGIN
    SELECT commission_rate INTO v_rate
    FROM BonusTier
    WHERE p_attainment >= min_attainment 
      AND p_attainment < max_attainment
      AND is_active = TRUE
    ORDER BY min_attainment DESC
    LIMIT 1;
    
    RETURN COALESCE(v_rate, 0);
END;
$$ LANGUAGE plpgsql;

-- ============================================================
-- MAIN STORED PROCEDURE: Calculate Monthly IC Payout
-- ============================================================
CREATE OR REPLACE PROCEDURE sp_CalculateMonthlyIC(
    p_year INTEGER,
    p_month INTEGER,
    p_recalculate BOOLEAN DEFAULT FALSE
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_start_date DATE;
    v_end_date DATE;
    v_count INTEGER;
    rec RECORD;
BEGIN
    -- Calculate date range
    v_start_date := make_date(p_year, p_month, 1);
    v_end_date := (v_start_date + INTERVAL '1 month - 1 day')::DATE;
    
    RAISE NOTICE 'Calculating IC for period: % to %', v_start_date, v_end_date;
    
    -- Clear existing calculations if recalculating
    IF p_recalculate THEN
        DELETE FROM PayoutReport 
        WHERE payout_year = p_year AND payout_month = p_month;
        RAISE NOTICE 'Cleared existing calculations for recalculation';
    END IF;
    
    -- ============================================================
    -- STEP 1: Calculate Sales Rep Commissions
    -- ============================================================
    INSERT INTO PayoutReport (
        emp_id, payout_year, payout_month,
        total_sales, total_units, total_target, attainment_pct,
        district_rank, region_rank, company_rank, performance_quartile,
        base_commission, tier_bonus, total_payout, status
    )
    WITH SalesAgg AS (
        -- Aggregate sales by rep for the month
        SELECT 
            s.emp_id,
            SUM(s.total_amount) as total_sales,
            SUM(s.quantity) as total_units
        FROM Sales s
        WHERE s.sale_date BETWEEN v_start_date AND v_end_date
        GROUP BY s.emp_id
    ),
    TargetAgg AS (
        -- Get targets for the month
        SELECT 
            emp_id,
            SUM(target_amount) as total_target
        FROM SalesTarget
        WHERE target_year = p_year AND target_month = p_month
        GROUP BY emp_id
    ),
    AttainmentCalc AS (
        -- Calculate attainment and join with rankings
        SELECT 
            e.emp_id,
            COALESCE(sa.total_sales, 0) as total_sales,
            COALESCE(sa.total_units, 0) as total_units,
            COALESCE(ta.total_target, 0) as total_target,
            fn_CalcAttainment(COALESCE(sa.total_sales, 0), COALESCE(ta.total_target, 1)) as attainment_pct,
            t.territory_id,
            d.district_id,
            r.region_id
        FROM Employee e
        LEFT JOIN SalesAgg sa ON e.emp_id = sa.emp_id
        LEFT JOIN TargetAgg ta ON e.emp_id = ta.emp_id
        LEFT JOIN Territory t ON e.territory_id = t.territory_id
        LEFT JOIN District d ON t.district_id = d.district_id
        LEFT JOIN Region r ON d.region_id = r.region_id
        WHERE e.role = 'Sales Rep' AND e.is_active = TRUE
    ),
    RankedReps AS (
        -- Apply window functions for rankings
        SELECT 
            ac.*,
            RANK() OVER (PARTITION BY ac.district_id ORDER BY ac.total_sales DESC) as district_rank,
            DENSE_RANK() OVER (PARTITION BY ac.region_id ORDER BY ac.total_sales DESC) as region_rank,
            RANK() OVER (ORDER BY ac.total_sales DESC) as company_rank,
            NTILE(4) OVER (ORDER BY ac.total_sales DESC) as performance_quartile
        FROM AttainmentCalc ac
    )
    SELECT 
        rr.emp_id,
        p_year,
        p_month,
        rr.total_sales,
        rr.total_units,
        rr.total_target,
        rr.attainment_pct,
        rr.district_rank,
        rr.region_rank,
        rr.company_rank,
        rr.performance_quartile,
        -- Base commission = Sales * Product commission rate
        ROUND(rr.total_sales * 0.03, 2) as base_commission, -- 3% base
        -- Tier bonus based on attainment
        ROUND(rr.total_sales * fn_GetCommissionRate(rr.attainment_pct), 2) as tier_bonus,
        -- Total = Base + Tier
        ROUND(rr.total_sales * 0.03 + rr.total_sales * fn_GetCommissionRate(rr.attainment_pct), 2) as total_payout,
        'Calculated'
    FROM RankedReps rr
    ON CONFLICT (emp_id, payout_year, payout_month) 
    DO UPDATE SET
        total_sales = EXCLUDED.total_sales,
        total_units = EXCLUDED.total_units,
        total_target = EXCLUDED.total_target,
        attainment_pct = EXCLUDED.attainment_pct,
        district_rank = EXCLUDED.district_rank,
        region_rank = EXCLUDED.region_rank,
        company_rank = EXCLUDED.company_rank,
        performance_quartile = EXCLUDED.performance_quartile,
        base_commission = EXCLUDED.base_commission,
        tier_bonus = EXCLUDED.tier_bonus,
        total_payout = EXCLUDED.total_payout,
        calculation_date = CURRENT_TIMESTAMP,
        status = 'Calculated';
    
    GET DIAGNOSTICS v_count = ROW_COUNT;
    RAISE NOTICE 'Calculated commissions for % sales reps', v_count;
    
    -- ============================================================
    -- STEP 2: Calculate Manager Override Commissions
    -- ============================================================
    UPDATE PayoutReport pr
    SET override_commission = mgr_calc.override_amount,
        total_payout = pr.base_commission + pr.tier_bonus + mgr_calc.override_amount
    FROM (
        SELECT 
            e.emp_id as manager_id,
            ROUND(SUM(sub_pr.total_sales) * 0.005, 2) as override_amount -- 0.5% override
        FROM Employee e
        JOIN fn_GetAllReports(e.emp_id) reports ON TRUE
        JOIN PayoutReport sub_pr ON reports.emp_id = sub_pr.emp_id
            AND sub_pr.payout_year = p_year 
            AND sub_pr.payout_month = p_month
        WHERE e.role IN ('District Manager', 'Regional Director', 'VP Sales')
          AND e.is_active = TRUE
        GROUP BY e.emp_id
    ) mgr_calc
    WHERE pr.emp_id = mgr_calc.manager_id
      AND pr.payout_year = p_year
      AND pr.payout_month = p_month;
    
    -- Insert manager records if they don't exist
    INSERT INTO PayoutReport (
        emp_id, payout_year, payout_month,
        total_sales, total_units, total_target, attainment_pct,
        base_commission, tier_bonus, override_commission, total_payout, status
    )
    SELECT 
        e.emp_id,
        p_year,
        p_month,
        COALESCE(SUM(sub_pr.total_sales), 0),
        COALESCE(SUM(sub_pr.total_units), 0),
        0, -- Managers don't have direct targets
        0,
        0,
        0,
        ROUND(COALESCE(SUM(sub_pr.total_sales), 0) * 0.005, 2), -- 0.5% override
        ROUND(COALESCE(SUM(sub_pr.total_sales), 0) * 0.005, 2),
        'Calculated'
    FROM Employee e
    CROSS JOIN LATERAL fn_GetAllReports(e.emp_id) reports
    LEFT JOIN PayoutReport sub_pr ON reports.emp_id = sub_pr.emp_id
        AND sub_pr.payout_year = p_year 
        AND sub_pr.payout_month = p_month
    WHERE e.role IN ('District Manager', 'Regional Director', 'VP Sales')
      AND e.is_active = TRUE
      AND NOT EXISTS (
          SELECT 1 FROM PayoutReport pr2 
          WHERE pr2.emp_id = e.emp_id 
            AND pr2.payout_year = p_year 
            AND pr2.payout_month = p_month
      )
    GROUP BY e.emp_id
    ON CONFLICT (emp_id, payout_year, payout_month) DO NOTHING;
    
    -- Log the calculation
    INSERT INTO ICCalcAuditLog (emp_id, action, new_value, performed_by)
    VALUES (NULL, 'BATCH_CALCULATION', 
            jsonb_build_object('year', p_year, 'month', p_month, 'reps_calculated', v_count),
            'SYSTEM');
    
    RAISE NOTICE 'IC Calculation completed for %/%', p_month, p_year;
END;
$$;

COMMENT ON PROCEDURE sp_CalculateMonthlyIC IS 
'Main IC Engine: Calculates monthly commissions for all reps with tiered bonuses and manager overrides';

-- ============================================================
-- FUNCTION 5: Generate Payout Report
-- ============================================================
CREATE OR REPLACE FUNCTION fn_GeneratePayoutReport(
    p_year INTEGER,
    p_month INTEGER
)
RETURNS TABLE (
    emp_code VARCHAR,
    emp_name VARCHAR,
    role VARCHAR,
    territory VARCHAR,
    district VARCHAR,
    region VARCHAR,
    total_sales DECIMAL,
    target DECIMAL,
    attainment VARCHAR,
    district_rank INTEGER,
    quartile INTEGER,
    base_commission DECIMAL,
    tier_bonus DECIMAL,
    override_commission DECIMAL,
    total_payout DECIMAL,
    status VARCHAR
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        e.emp_code,
        (e.first_name || ' ' || e.last_name)::VARCHAR as emp_name,
        e.role::VARCHAR,
        COALESCE(t.territory_name, 'N/A')::VARCHAR as territory,
        COALESCE(d.district_name, 'N/A')::VARCHAR as district,
        COALESCE(r.region_name, 'N/A')::VARCHAR as region,
        pr.total_sales,
        pr.total_target as target,
        (ROUND(pr.attainment_pct * 100, 1) || '%')::VARCHAR as attainment,
        pr.district_rank,
        pr.performance_quartile as quartile,
        pr.base_commission,
        pr.tier_bonus,
        COALESCE(pr.override_commission, 0) as override_commission,
        pr.total_payout,
        pr.status::VARCHAR
    FROM PayoutReport pr
    JOIN Employee e ON pr.emp_id = e.emp_id
    LEFT JOIN Territory t ON e.territory_id = t.territory_id
    LEFT JOIN District d ON t.district_id = d.district_id
    LEFT JOIN Region r ON d.region_id = r.region_id
    WHERE pr.payout_year = p_year AND pr.payout_month = p_month
    ORDER BY pr.total_payout DESC;
END;
$$ LANGUAGE plpgsql;

-- ============================================================
-- FUNCTION 6: Get Historical Territory Assignment
-- (For SCD Type 2 lookups)
-- ============================================================
CREATE OR REPLACE FUNCTION fn_GetHistoricalAssignment(
    p_emp_id INTEGER,
    p_as_of_date DATE
)
RETURNS TABLE (
    emp_id INTEGER,
    role VARCHAR,
    territory_id INTEGER,
    manager_id INTEGER,
    base_salary DECIMAL
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        eh.emp_id,
        eh.role::VARCHAR,
        eh.territory_id,
        eh.manager_id,
        eh.base_salary
    FROM EmployeeHistory eh
    WHERE eh.emp_id = p_emp_id
      AND eh.effective_start_date <= p_as_of_date
      AND (eh.effective_end_date IS NULL OR eh.effective_end_date > p_as_of_date)
    LIMIT 1;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION fn_GetHistoricalAssignment IS 
'SCD Type 2 lookup: Gets employee assignment as of a specific date';
