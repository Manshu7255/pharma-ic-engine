"""
Pharmaceutical IC Engine - Data Generator
Generates realistic dummy data for the IC system
"""

import random
from datetime import datetime, timedelta
from typing import List, Tuple
import json

# Configuration
NUM_REGIONS = 5
NUM_DISTRICTS_PER_REGION = 3
NUM_TERRITORIES_PER_DISTRICT = 4
NUM_REPS_PER_TERRITORY = 2
NUM_PRODUCTS = 10
NUM_MONTHS = 12  # 12 months of data
START_YEAR = 2025

# Sample data
REGION_NAMES = ["Northeast", "Southeast", "Midwest", "Southwest", "West"]
FIRST_NAMES = ["James", "Mary", "John", "Patricia", "Robert", "Jennifer", "Michael", "Linda", 
               "William", "Elizabeth", "David", "Barbara", "Richard", "Susan", "Joseph", "Jessica",
               "Thomas", "Sarah", "Charles", "Karen", "Christopher", "Nancy", "Daniel", "Lisa"]
LAST_NAMES = ["Smith", "Johnson", "Williams", "Brown", "Jones", "Garcia", "Miller", "Davis",
              "Rodriguez", "Martinez", "Hernandez", "Lopez", "Gonzalez", "Wilson", "Anderson",
              "Thomas", "Taylor", "Moore", "Jackson", "Martin", "Lee", "Perez", "Thompson", "White"]

THERAPEUTIC_CLASSES = ["Cardiology", "Oncology", "Neurology", "Immunology", "Endocrinology",
                       "Respiratory", "Gastroenterology", "Dermatology", "Ophthalmology", "Psychiatry"]

PRODUCT_NAMES = [
    ("Cardiomax", "Atorvastatin", "Cardiology"),
    ("Oncocel", "Pembrolizumab", "Oncology"),
    ("Neurozen", "Levetiracetam", "Neurology"),
    ("Immunoforce", "Adalimumab", "Immunology"),
    ("Diabetrol", "Metformin", "Endocrinology"),
    ("Respira", "Budesonide", "Respiratory"),
    ("Gastroaid", "Omeprazole", "Gastroenterology"),
    ("Dermacare", "Dupilumab", "Dermatology"),
    ("Visiomax", "Ranibizumab", "Ophthalmology"),
    ("Mindwell", "Sertraline", "Psychiatry")
]


def generate_regions() -> str:
    """Generate INSERT statements for regions"""
    sql = "-- Regions\nINSERT INTO Region (region_id, region_name, region_code) VALUES\n"
    values = []
    for i, name in enumerate(REGION_NAMES[:NUM_REGIONS], 1):
        code = name[:2].upper() + str(i).zfill(2)
        values.append(f"({i}, '{name}', '{code}')")
    sql += ",\n".join(values) + ";\n"
    return sql


def generate_districts() -> str:
    """Generate INSERT statements for districts"""
    sql = "\n-- Districts\nINSERT INTO District (district_id, region_id, district_name, district_code) VALUES\n"
    values = []
    district_id = 1
    for region_id in range(1, NUM_REGIONS + 1):
        for d in range(1, NUM_DISTRICTS_PER_REGION + 1):
            name = f"{REGION_NAMES[region_id-1]} District {d}"
            code = f"D{str(district_id).zfill(3)}"
            values.append(f"({district_id}, {region_id}, '{name}', '{code}')")
            district_id += 1
    sql += ",\n".join(values) + ";\n"
    return sql


def generate_territories() -> str:
    """Generate INSERT statements for territories"""
    sql = "\n-- Territories\nINSERT INTO Territory (territory_id, district_id, territory_name, territory_code) VALUES\n"
    values = []
    territory_id = 1
    num_districts = NUM_REGIONS * NUM_DISTRICTS_PER_REGION
    for district_id in range(1, num_districts + 1):
        for t in range(1, NUM_TERRITORIES_PER_DISTRICT + 1):
            name = f"Territory {territory_id}"
            code = f"T{str(territory_id).zfill(4)}"
            values.append(f"({territory_id}, {district_id}, '{name}', '{code}')")
            territory_id += 1
    sql += ",\n".join(values) + ";\n"
    return sql


def generate_products() -> str:
    """Generate INSERT statements for products"""
    sql = "\n-- Products\nINSERT INTO Product (product_id, product_code, product_name, generic_name, therapeutic_class, base_commission_rate) VALUES\n"
    values = []
    for i, (name, generic, therapeutic) in enumerate(PRODUCT_NAMES[:NUM_PRODUCTS], 1):
        code = f"PRD{str(i).zfill(3)}"
        rate = round(random.uniform(0.03, 0.08), 4)  # 3-8% commission
        values.append(f"({i}, '{code}', '{name}', '{generic}', '{therapeutic}', {rate})")
    sql += ",\n".join(values) + ";\n"
    return sql


def generate_bonus_tiers() -> str:
    """Generate INSERT statements for bonus tiers"""
    sql = "\n-- Bonus Tiers\nINSERT INTO BonusTier (tier_id, tier_name, min_attainment, max_attainment, commission_rate, bonus_multiplier) VALUES\n"
    tiers = [
        (1, "Below Threshold", 0.00, 0.50, 0.00, 0.00),
        (2, "Threshold", 0.50, 0.80, 0.01, 0.50),
        (3, "Target", 0.80, 1.00, 0.02, 1.00),
        (4, "Above Target", 1.00, 1.20, 0.03, 1.25),
        (5, "Excellence", 1.20, 1.50, 0.04, 1.50),
        (6, "Outstanding", 1.50, 10.00, 0.05, 2.00)
    ]
    values = [f"({t[0]}, '{t[1]}', {t[2]}, {t[3]}, {t[4]}, {t[5]})" for t in tiers]
    sql += ",\n".join(values) + ";\n"
    return sql


def generate_employees() -> Tuple[str, List[dict]]:
    """Generate INSERT statements for employees with hierarchy"""
    employees = []
    emp_id = 1
    
    # VP Sales (1)
    vp = {
        "emp_id": emp_id,
        "code": "VP001",
        "first": random.choice(FIRST_NAMES),
        "last": random.choice(LAST_NAMES),
        "role": "VP Sales",
        "manager_id": None,
        "territory_id": None,
        "salary": 250000
    }
    employees.append(vp)
    vp_id = emp_id
    emp_id += 1
    
    # Regional Directors (5)
    rd_ids = []
    for r in range(NUM_REGIONS):
        rd = {
            "emp_id": emp_id,
            "code": f"RD{str(emp_id).zfill(3)}",
            "first": random.choice(FIRST_NAMES),
            "last": random.choice(LAST_NAMES),
            "role": "Regional Director",
            "manager_id": vp_id,
            "territory_id": None,
            "salary": random.randint(150000, 180000)
        }
        employees.append(rd)
        rd_ids.append(emp_id)
        emp_id += 1
    
    # District Managers (15)
    dm_ids = []
    district_id = 1
    for rd_idx, rd_id in enumerate(rd_ids):
        for d in range(NUM_DISTRICTS_PER_REGION):
            dm = {
                "emp_id": emp_id,
                "code": f"DM{str(emp_id).zfill(3)}",
                "first": random.choice(FIRST_NAMES),
                "last": random.choice(LAST_NAMES),
                "role": "District Manager",
                "manager_id": rd_id,
                "territory_id": None,
                "salary": random.randint(100000, 130000)
            }
            employees.append(dm)
            dm_ids.append((emp_id, district_id))
            emp_id += 1
            district_id += 1
    
    # Sales Reps
    territory_id = 1
    dm_index = 0
    for dm_id, dist_id in dm_ids:
        for t in range(NUM_TERRITORIES_PER_DISTRICT):
            for rep in range(NUM_REPS_PER_TERRITORY):
                rep_data = {
                    "emp_id": emp_id,
                    "code": f"SR{str(emp_id).zfill(4)}",
                    "first": random.choice(FIRST_NAMES),
                    "last": random.choice(LAST_NAMES),
                    "role": "Sales Rep",
                    "manager_id": dm_id,
                    "territory_id": territory_id,
                    "salary": random.randint(60000, 85000)
                }
                employees.append(rep_data)
                emp_id += 1
            territory_id += 1
    
    # Generate SQL
    sql = "\n-- Employees\nINSERT INTO Employee (emp_id, emp_code, first_name, last_name, email, role, manager_id, territory_id, hire_date, base_salary) VALUES\n"
    values = []
    for e in employees:
        hire_date = f"2020-{random.randint(1,12):02d}-{random.randint(1,28):02d}"
        email = f"{e['first'].lower()}.{e['last'].lower()}{e['emp_id']}@pharma.com"
        mgr = "NULL" if e['manager_id'] is None else e['manager_id']
        terr = "NULL" if e['territory_id'] is None else e['territory_id']
        values.append(f"({e['emp_id']}, '{e['code']}', '{e['first']}', '{e['last']}', '{email}', '{e['role']}', {mgr}, {terr}, '{hire_date}', {e['salary']})")
    
    sql += ",\n".join(values) + ";\n"
    return sql, employees


def generate_product_alignments(employees: List[dict]) -> str:
    """Generate product alignments for reps"""
    sql = "\n-- Product Alignments\nINSERT INTO ProductAlignment (emp_id, product_id, effective_start_date, is_current, primary_product) VALUES\n"
    values = []
    align_id = 1
    
    for emp in employees:
        if emp['role'] == 'Sales Rep':
            # Each rep handles 2-4 products
            num_products = random.randint(2, 4)
            products = random.sample(range(1, NUM_PRODUCTS + 1), num_products)
            for i, prod_id in enumerate(products):
                is_primary = "TRUE" if i == 0 else "FALSE"
                values.append(f"({emp['emp_id']}, {prod_id}, '2024-01-01', TRUE, {is_primary})")
    
    sql += ",\n".join(values) + ";\n"
    return sql


def generate_sales_targets(employees: List[dict]) -> str:
    """Generate monthly sales targets"""
    sql = "\n-- Sales Targets\nINSERT INTO SalesTarget (emp_id, product_id, target_year, target_month, target_amount, target_units, stretch_target) VALUES\n"
    values = []
    
    reps = [e for e in employees if e['role'] == 'Sales Rep']
    
    for emp in reps:
        # Get a random product for this rep
        product_id = random.randint(1, NUM_PRODUCTS)
        for month in range(1, NUM_MONTHS + 1):
            base_target = random.randint(50000, 150000)
            units = random.randint(100, 500)
            stretch = int(base_target * 1.2)
            values.append(f"({emp['emp_id']}, {product_id}, {START_YEAR}, {month}, {base_target}, {units}, {stretch})")
    
    sql += ",\n".join(values) + ";\n"
    return sql


def generate_sales(employees: List[dict]) -> str:
    """Generate actual sales transactions"""
    sql = "\n-- Sales Transactions\nINSERT INTO Sales (emp_id, product_id, territory_id, sale_date, prescription_id, physician_id, quantity, unit_price, is_new_prescription) VALUES\n"
    values = []
    
    reps = [e for e in employees if e['role'] == 'Sales Rep']
    sale_id = 1
    
    for emp in reps:
        if emp['territory_id'] is None:
            continue
            
        # Generate 20-50 sales per rep per month
        for month in range(1, NUM_MONTHS + 1):
            num_sales = random.randint(20, 50)
            for _ in range(num_sales):
                day = random.randint(1, 28)
                sale_date = f"{START_YEAR}-{month:02d}-{day:02d}"
                product_id = random.randint(1, NUM_PRODUCTS)
                rx_id = f"RX{sale_id:08d}"
                physician_id = f"HCP{random.randint(1000, 9999)}"
                quantity = random.randint(1, 20)
                unit_price = round(random.uniform(50, 500), 2)
                is_new = "TRUE" if random.random() < 0.3 else "FALSE"
                
                values.append(f"({emp['emp_id']}, {product_id}, {emp['territory_id']}, '{sale_date}', '{rx_id}', '{physician_id}', {quantity}, {unit_price}, {is_new})")
                sale_id += 1
    
    sql += ",\n".join(values) + ";\n"
    return sql


def main():
    """Generate all SQL files"""
    print("Generating Pharmaceutical IC Engine Data...")
    
    # Generate all data
    regions_sql = generate_regions()
    districts_sql = generate_districts()
    territories_sql = generate_territories()
    products_sql = generate_products()
    bonus_tiers_sql = generate_bonus_tiers()
    employees_sql, employees = generate_employees()
    alignments_sql = generate_product_alignments(employees)
    targets_sql = generate_sales_targets(employees)
    sales_sql = generate_sales(employees)
    
    # Combine into one file
    full_sql = f"""-- ============================================================
-- PHARMACEUTICAL IC ENGINE - SAMPLE DATA
-- Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}
-- ============================================================

{regions_sql}
{districts_sql}
{territories_sql}
{products_sql}
{bonus_tiers_sql}
{employees_sql}
{alignments_sql}
{targets_sql}
{sales_sql}

-- Reset sequences after bulk insert
SELECT setval('region_region_id_seq', (SELECT MAX(region_id) FROM Region));
SELECT setval('district_district_id_seq', (SELECT MAX(district_id) FROM District));
SELECT setval('territory_territory_id_seq', (SELECT MAX(territory_id) FROM Territory));
SELECT setval('employee_emp_id_seq', (SELECT MAX(emp_id) FROM Employee));
SELECT setval('product_product_id_seq', (SELECT MAX(product_id) FROM Product));

-- Verify data
SELECT 'Regions' as table_name, COUNT(*) as count FROM Region
UNION ALL SELECT 'Districts', COUNT(*) FROM District
UNION ALL SELECT 'Territories', COUNT(*) FROM Territory
UNION ALL SELECT 'Products', COUNT(*) FROM Product
UNION ALL SELECT 'Employees', COUNT(*) FROM Employee
UNION ALL SELECT 'Sales Targets', COUNT(*) FROM SalesTarget
UNION ALL SELECT 'Sales', COUNT(*) FROM Sales
UNION ALL SELECT 'Bonus Tiers', COUNT(*) FROM BonusTier;
"""
    
    # Write to file
    with open("03_sample_data.sql", "w", encoding="utf-8") as f:
        f.write(full_sql)
    
    print(f"Generated data for:")
    print(f"  - {NUM_REGIONS} Regions")
    print(f"  - {NUM_REGIONS * NUM_DISTRICTS_PER_REGION} Districts")
    print(f"  - {NUM_REGIONS * NUM_DISTRICTS_PER_REGION * NUM_TERRITORIES_PER_DISTRICT} Territories")
    print(f"  - {len(employees)} Employees")
    print(f"  - {NUM_PRODUCTS} Products")
    print(f"  - {NUM_MONTHS} months of sales data")
    print("\nOutput: 03_sample_data.sql")


if __name__ == "__main__":
    main()
