# ER Diagram - Pharmaceutical IC Engine

Here's how all the pieces fit together. I'll walk through each section.

## The Big Picture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              IC ENGINE SCHEMA                                │
└─────────────────────────────────────────────────────────────────────────────┘

    GEOGRAPHY                    PEOPLE                      MONEY
    ─────────                    ──────                      ─────
    Region                       Employee ←──┐               BonusTier
       │                            │        │ (self-ref)    PayoutReport
       ▼                            ▼        │               
    District                    EmployeeHistory              
       │                            
       ▼                        ProductAlignment             
    Territory ◄─────────────────────┘
                                
    PRODUCTS                    TRANSACTIONS
    ────────                    ────────────
    Product ◄───────────────── Sales
       │                       SalesTarget
       └───────────────────────────┘
```

## Geography: Where Reps Work

Pretty straightforward hierarchy:

```
Region (5 total)
   └── District (3 per region = 15)
          └── Territory (4 per district = 60)
```

Each sales rep is assigned to one territory. Territories don't overlap.

## The Employee Hierarchy

This is where it gets interesting. We have 4 levels:

```
VP Sales (1 person)
    └── Regional Directors (5)
           └── District Managers (15)
                  └── Sales Reps (120)
```

The `manager_id` field creates a self-referencing relationship. A recursive CTE can climb this tree to figure out everyone's reporting chain.

### Why We Need EmployeeHistory (SCD Type 2)

Reps change territories. Managers get promoted. We need to know what someone's assignment was *at a specific point in time*.

Example: Rep #101 moved from Territory 5 to Territory 12 on June 1st.

| history_id | emp_id | territory_id | effective_start | effective_end | is_current |
|------------|--------|--------------|-----------------|---------------|------------|
| 45 | 101 | 5 | 2024-01-01 | 2025-05-31 | FALSE |
| 78 | 101 | 12 | 2025-06-01 | NULL | TRUE |

When calculating Q1 commission, we use the old territory. For Q2, the new one.

## Products and Alignments

Each rep sells 2-4 products. This can change over time (just like territories), so ProductAlignment also uses SCD Type 2.

```
Product (10 pharmaceutical products)
    │
    └── ProductAlignment (who sells what, and since when)
```

## Transactions: Where the Money Comes From

**SalesTarget** - What each rep is expected to sell each month. Set by management.

**Sales** - Actual prescription sales. Each row is a single Rx filled.

We compare actual vs. target to get "attainment percentage" - the basis for commission tiers.

## Compensation Tables

**BonusTier** - The commission structure:
| Tier | Attainment | Rate |
|------|------------|------|
| Below Threshold | 0-50% | 0% |
| Threshold | 50-80% | 1% |
| Target | 80-100% | 2% |
| Excellence | 100-120% | 3% |
| Outstanding | 120%+ | 5% |

**PayoutReport** - The output of each IC calculation run. Stores total sales, attainment, rank, and final payout for each rep/month.

## Key Constraints

A few things the database enforces:

- Every sale has a valid rep and product (foreign keys)
- One target per rep/product/month (unique constraint)
- One payout record per rep/month (unique constraint)
- Employee emails are unique
- Attainment ranges don't overlap in BonusTier

## Indexes Worth Noting

The optimization report goes deeper, but the key ones:

- **Covering index on Sales** - Lets us aggregate sales without touching the main table
- **Partial index on Employee** - Only indexes `is_active = TRUE` rows
- **Composite index on SalesTarget** - Fast lookups by (emp_id, year, month)

---

That's the schema. The `01_schema.sql` file has all the CREATE statements if you want the exact DDL.
