-- ============================================================
-- PHARMACEUTICAL INCENTIVE COMPENSATION (IC) ENGINE
-- Database: PostgreSQL
-- Version: 1.0
-- Description: Complete IC system for pharma sales compensation
-- ============================================================

-- Enable extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ============================================================
-- PART 1: CORE REFERENCE TABLES
-- ============================================================

-- Regions (Top level geography)
CREATE TABLE Region (
    region_id SERIAL PRIMARY KEY,
    region_name VARCHAR(100) NOT NULL UNIQUE,
    region_code VARCHAR(10) NOT NULL UNIQUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Districts (Within regions)
CREATE TABLE District (
    district_id SERIAL PRIMARY KEY,
    region_id INTEGER NOT NULL REFERENCES Region(region_id),
    district_name VARCHAR(100) NOT NULL,
    district_code VARCHAR(10) NOT NULL UNIQUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Territories (Sales areas within districts)
CREATE TABLE Territory (
    territory_id SERIAL PRIMARY KEY,
    district_id INTEGER NOT NULL REFERENCES District(district_id),
    territory_name VARCHAR(100) NOT NULL,
    territory_code VARCHAR(20) NOT NULL UNIQUE,
    zip_codes TEXT[], -- Array of zip codes covered
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ============================================================
-- PART 2: EMPLOYEE TABLES (WITH SCD TYPE 2)
-- ============================================================

-- Employee Master (Current state)
CREATE TABLE Employee (
    emp_id SERIAL PRIMARY KEY,
    emp_code VARCHAR(20) NOT NULL UNIQUE,
    first_name VARCHAR(50) NOT NULL,
    last_name VARCHAR(50) NOT NULL,
    email VARCHAR(100) UNIQUE,
    phone VARCHAR(20),
    role VARCHAR(50) NOT NULL CHECK (role IN ('Sales Rep', 'District Manager', 'Regional Director', 'VP Sales')),
    manager_id INTEGER REFERENCES Employee(emp_id),
    territory_id INTEGER REFERENCES Territory(territory_id),
    hire_date DATE NOT NULL,
    termination_date DATE,
    is_active BOOLEAN DEFAULT TRUE,
    base_salary DECIMAL(12,2),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Employee History (SCD Type 2 - Slowly Changing Dimension)
CREATE TABLE EmployeeHistory (
    history_id SERIAL PRIMARY KEY,
    emp_id INTEGER NOT NULL REFERENCES Employee(emp_id),
    emp_code VARCHAR(20) NOT NULL,
    role VARCHAR(50) NOT NULL,
    manager_id INTEGER,
    territory_id INTEGER,
    base_salary DECIMAL(12,2),
    effective_start_date DATE NOT NULL,
    effective_end_date DATE, -- NULL means current
    is_current BOOLEAN DEFAULT TRUE,
    change_reason VARCHAR(200),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ============================================================
-- PART 3: PRODUCT TABLES
-- ============================================================

-- Products (Pharmaceutical products)
CREATE TABLE Product (
    product_id SERIAL PRIMARY KEY,
    product_code VARCHAR(20) NOT NULL UNIQUE,
    product_name VARCHAR(200) NOT NULL,
    generic_name VARCHAR(200),
    therapeutic_class VARCHAR(100),
    launch_date DATE,
    is_active BOOLEAN DEFAULT TRUE,
    base_commission_rate DECIMAL(5,4) DEFAULT 0.05, -- 5% default
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Product Alignment (Rep-to-Product assignments - SCD Type 2)
CREATE TABLE ProductAlignment (
    alignment_id SERIAL PRIMARY KEY,
    emp_id INTEGER NOT NULL REFERENCES Employee(emp_id),
    product_id INTEGER NOT NULL REFERENCES Product(product_id),
    effective_start_date DATE NOT NULL,
    effective_end_date DATE, -- NULL means current
    is_current BOOLEAN DEFAULT TRUE,
    primary_product BOOLEAN DEFAULT FALSE, -- Is this rep's main product?
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(emp_id, product_id, effective_start_date)
);

-- ============================================================
-- PART 4: SALES TARGETS AND QUOTAS
-- ============================================================

-- Sales Targets (Monthly quotas per rep per product)
CREATE TABLE SalesTarget (
    target_id SERIAL PRIMARY KEY,
    emp_id INTEGER NOT NULL REFERENCES Employee(emp_id),
    product_id INTEGER NOT NULL REFERENCES Product(product_id),
    target_year INTEGER NOT NULL,
    target_month INTEGER NOT NULL CHECK (target_month BETWEEN 1 AND 12),
    target_amount DECIMAL(15,2) NOT NULL, -- Dollar target
    target_units INTEGER, -- Unit target (prescriptions)
    stretch_target DECIMAL(15,2), -- Bonus target (120% of base)
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(emp_id, product_id, target_year, target_month)
);

-- ============================================================
-- PART 5: SALES TRANSACTIONS
-- ============================================================

-- Sales (Actual prescription sales)
CREATE TABLE Sales (
    sale_id SERIAL PRIMARY KEY,
    emp_id INTEGER NOT NULL REFERENCES Employee(emp_id),
    product_id INTEGER NOT NULL REFERENCES Product(product_id),
    territory_id INTEGER NOT NULL REFERENCES Territory(territory_id),
    sale_date DATE NOT NULL,
    prescription_id VARCHAR(50), -- External Rx ID
    physician_id VARCHAR(50), -- HCP identifier
    pharmacy_id VARCHAR(50),
    quantity INTEGER NOT NULL,
    unit_price DECIMAL(10,2) NOT NULL,
    total_amount DECIMAL(15,2) GENERATED ALWAYS AS (quantity * unit_price) STORED,
    is_new_prescription BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ============================================================
-- PART 6: BONUS TIERS AND COMMISSION RULES
-- ============================================================

-- Bonus Tiers (Commission rate by attainment level)
CREATE TABLE BonusTier (
    tier_id SERIAL PRIMARY KEY,
    tier_name VARCHAR(50) NOT NULL,
    min_attainment DECIMAL(5,2) NOT NULL, -- e.g., 0.00 = 0%
    max_attainment DECIMAL(5,2) NOT NULL, -- e.g., 1.00 = 100%
    commission_rate DECIMAL(5,4) NOT NULL, -- e.g., 0.0300 = 3%
    bonus_multiplier DECIMAL(4,2) DEFAULT 1.00,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CHECK (max_attainment > min_attainment)
);

-- Commission Rules (Additional rules by role/product)
CREATE TABLE CommissionRules (
    rule_id SERIAL PRIMARY KEY,
    rule_name VARCHAR(100) NOT NULL,
    role VARCHAR(50), -- NULL means applies to all
    product_id INTEGER REFERENCES Product(product_id), -- NULL means all products
    rule_type VARCHAR(50) NOT NULL CHECK (rule_type IN ('Override', 'SPIFF', 'Accelerator', 'Cap')),
    rate DECIMAL(5,4),
    flat_amount DECIMAL(10,2),
    effective_start_date DATE NOT NULL,
    effective_end_date DATE,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ============================================================
-- PART 7: PAYOUT REPORTS (OUTPUT)
-- ============================================================

-- Payout Report (Monthly commission calculations)
CREATE TABLE PayoutReport (
    payout_id SERIAL PRIMARY KEY,
    emp_id INTEGER NOT NULL REFERENCES Employee(emp_id),
    payout_year INTEGER NOT NULL,
    payout_month INTEGER NOT NULL,
    
    -- Sales Summary
    total_sales DECIMAL(15,2) NOT NULL,
    total_units INTEGER,
    total_target DECIMAL(15,2) NOT NULL,
    attainment_pct DECIMAL(7,4) NOT NULL, -- e.g., 1.2500 = 125%
    
    -- Rankings
    district_rank INTEGER,
    region_rank INTEGER,
    company_rank INTEGER,
    performance_quartile INTEGER CHECK (performance_quartile BETWEEN 1 AND 4),
    
    -- Commissions
    base_commission DECIMAL(12,2) NOT NULL,
    tier_bonus DECIMAL(12,2) DEFAULT 0,
    override_commission DECIMAL(12,2) DEFAULT 0, -- For managers
    spiff_bonus DECIMAL(12,2) DEFAULT 0,
    total_payout DECIMAL(12,2) NOT NULL,
    
    -- Metadata
    calculation_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    status VARCHAR(20) DEFAULT 'Calculated' CHECK (status IN ('Calculated', 'Approved', 'Paid', 'Disputed')),
    approved_by INTEGER REFERENCES Employee(emp_id),
    approved_at TIMESTAMP,
    notes TEXT,
    
    UNIQUE(emp_id, payout_year, payout_month)
);

-- Audit Log for IC calculations
CREATE TABLE ICCalcAuditLog (
    log_id SERIAL PRIMARY KEY,
    payout_id INTEGER REFERENCES PayoutReport(payout_id),
    emp_id INTEGER,
    action VARCHAR(50) NOT NULL,
    old_value JSONB,
    new_value JSONB,
    performed_by VARCHAR(100),
    performed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ============================================================
-- PART 8: INDEXES FOR PERFORMANCE
-- ============================================================

-- Covering index for sales queries (CRITICAL for performance)
CREATE INDEX idx_sales_covering ON Sales(emp_id, product_id, sale_date) 
    INCLUDE (quantity, unit_price, total_amount);

-- Sales date range queries
CREATE INDEX idx_sales_date ON Sales(sale_date);
CREATE INDEX idx_sales_emp_date ON Sales(emp_id, sale_date);

-- Employee hierarchy traversal
CREATE INDEX idx_employee_manager ON Employee(manager_id) WHERE is_active = TRUE;
CREATE INDEX idx_employee_territory ON Employee(territory_id) WHERE is_active = TRUE;

-- Employee history lookups (SCD Type 2)
CREATE INDEX idx_emp_history_current ON EmployeeHistory(emp_id, is_current) 
    WHERE is_current = TRUE;
CREATE INDEX idx_emp_history_dates ON EmployeeHistory(emp_id, effective_start_date, effective_end_date);

-- Product alignment lookups
CREATE INDEX idx_product_align_current ON ProductAlignment(emp_id, is_current) 
    WHERE is_current = TRUE;

-- Target lookups
CREATE INDEX idx_target_period ON SalesTarget(target_year, target_month);
CREATE INDEX idx_target_emp ON SalesTarget(emp_id, target_year, target_month);

-- Payout report queries
CREATE INDEX idx_payout_period ON PayoutReport(payout_year, payout_month);
CREATE INDEX idx_payout_emp ON PayoutReport(emp_id, payout_year, payout_month);

-- ============================================================
-- PART 9: VIEWS FOR REPORTING
-- ============================================================

-- View: Current Employee Details with Hierarchy
CREATE OR REPLACE VIEW vw_EmployeeHierarchy AS
WITH RECURSIVE EmpHierarchy AS (
    -- Base: Top-level (VP Sales has no manager)
    SELECT 
        emp_id, emp_code, first_name, last_name, role,
        manager_id, territory_id, base_salary,
        1 as level,
        ARRAY[emp_id] as path,
        first_name || ' ' || last_name as full_path
    FROM Employee 
    WHERE manager_id IS NULL AND is_active = TRUE
    
    UNION ALL
    
    -- Recursive: All reports
    SELECT 
        e.emp_id, e.emp_code, e.first_name, e.last_name, e.role,
        e.manager_id, e.territory_id, e.base_salary,
        eh.level + 1,
        eh.path || e.emp_id,
        eh.full_path || ' > ' || e.first_name || ' ' || e.last_name
    FROM Employee e
    JOIN EmpHierarchy eh ON e.manager_id = eh.emp_id
    WHERE e.is_active = TRUE
)
SELECT 
    eh.*,
    m.first_name || ' ' || m.last_name as manager_name,
    t.territory_name,
    d.district_name,
    r.region_name
FROM EmpHierarchy eh
LEFT JOIN Employee m ON eh.manager_id = m.emp_id
LEFT JOIN Territory t ON eh.territory_id = t.territory_id
LEFT JOIN District d ON t.district_id = d.district_id
LEFT JOIN Region r ON d.region_id = r.region_id;

-- View: Monthly Sales Summary with Rankings
CREATE OR REPLACE VIEW vw_MonthlySalesRanking AS
SELECT 
    e.emp_id,
    e.first_name || ' ' || e.last_name as rep_name,
    e.role,
    d.district_id,
    d.district_name,
    r.region_id,
    r.region_name,
    EXTRACT(YEAR FROM s.sale_date)::INTEGER as sale_year,
    EXTRACT(MONTH FROM s.sale_date)::INTEGER as sale_month,
    SUM(s.total_amount) as total_sales,
    SUM(s.quantity) as total_units,
    
    -- Window Functions for Rankings
    RANK() OVER (
        PARTITION BY d.district_id, EXTRACT(YEAR FROM s.sale_date), EXTRACT(MONTH FROM s.sale_date)
        ORDER BY SUM(s.total_amount) DESC
    ) as district_rank,
    
    DENSE_RANK() OVER (
        PARTITION BY r.region_id, EXTRACT(YEAR FROM s.sale_date), EXTRACT(MONTH FROM s.sale_date)
        ORDER BY SUM(s.total_amount) DESC
    ) as region_rank,
    
    RANK() OVER (
        PARTITION BY EXTRACT(YEAR FROM s.sale_date), EXTRACT(MONTH FROM s.sale_date)
        ORDER BY SUM(s.total_amount) DESC
    ) as company_rank,
    
    NTILE(4) OVER (
        PARTITION BY EXTRACT(YEAR FROM s.sale_date), EXTRACT(MONTH FROM s.sale_date)
        ORDER BY SUM(s.total_amount) DESC
    ) as performance_quartile

FROM Sales s
JOIN Employee e ON s.emp_id = e.emp_id
JOIN Territory t ON e.territory_id = t.territory_id
JOIN District d ON t.district_id = d.district_id
JOIN Region r ON d.region_id = r.region_id
WHERE e.role = 'Sales Rep'
GROUP BY 
    e.emp_id, e.first_name, e.last_name, e.role,
    d.district_id, d.district_name,
    r.region_id, r.region_name,
    EXTRACT(YEAR FROM s.sale_date),
    EXTRACT(MONTH FROM s.sale_date);

COMMENT ON VIEW vw_MonthlySalesRanking IS 'Monthly sales with RANK, DENSE_RANK, and NTILE for performance tiering';
