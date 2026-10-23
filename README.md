# Zepto Catalog Health Audit

**PostgreSQL + Excel | E-commerce inventory, pricing and availability analysis**

## Summary / Objective

Audit a messy, real-world quick-commerce catalog (3,732 Zepto product listings) with SQL to find where it leaks value through duplicated data, stock gaps, pricing behaviour and concentrated inventory, then turn the results into an Excel dashboard and an adjustable restock-priority model.

---

## Table of Contents

1. [Overview](#overview)
2. [Problem Statement](#problem-statement)
3. [Data Set](#data-set)
4. [Tools and Technologies](#tools-and-technologies)
5. [Project Structure](#project-structure)
6. [Loading the Data](#loading-the-data)
7. [Data Cleaning and Preparation](#data-cleaning-and-preparation)
8. [EDA (Exploratory Data Analysis)](#eda-exploratory-data-analysis)
9. [SQL Business Analysis](#sql-business-analysis)
10. [Dashboard](#dashboard)
11. [Results and Conclusion](#results-and-conclusion)
12. [Limitations](#limitations)
13. [How to Run](#how-to-run)
14. [Author and Contact](#author-and-contact)

---

## Overview

This project simulates how a data analyst in e-commerce or retail audits a product catalog. The raw data is loaded into PostgreSQL untouched, cleaned into two analysis-ready tables, explored, and queried to answer ten business questions. The results are exported to Excel, where they feed a one-page dashboard and a restock model whose weights can be changed to see the ranking update.

What makes this different from a typical SQL practice project:

- **Non-destructive cleaning.** The raw table is never modified. Cleaning builds new tables, so every script can be re-run safely.
- **Listings vs unique products.** The audit separates *listings* (rows a shopper sees) from *unique products* (what actually exists), which exposed that most products are copied across categories.
- **A data-quality log.** Every problem found is recorded in a `data_issues` table with the number of rows affected and the action taken.
- **Fair comparisons.** Price per 100g is compared inside each category, not across unrelated products.
- **Honest metrics.** Price × quantity is called a *stock value index*, not revenue.
- **SQL and Excel used for what each does best.** SQL cleans and calculates; Excel presents and lets stakeholders test assumptions.

## Problem Statement

A quick-commerce catalog changes constantly and is often duplicated and inconsistent. A category manager needs to know:

> **Where is the catalog leaking value: through messy data, stock gaps, pricing behaviour, or inventory concentration, and what should be fixed first?**

Specific questions include which categories run out of stock most, whether promoted products are available, how deep discounts really go, whether bigger packs are actually cheaper, and which out-of-stock products should be restocked first.

## Data Set

| Item | Detail |
|---|---|
| Source | Kaggle, originally scraped from Zepto's product listings *(add dataset link)* |
| File | `zepto_v2.csv` |
| Size | 3,732 rows, 9 columns, 14 categories |
| Grain | One row per product **listing** (the same product can appear in several categories) |
| Encoding | UTF-8 (with BOM) |

| Column | Description |
|---|---|
| `Category` | Product category (Fruits & Vegetables, Biscuits, Beverages, and so on) |
| `name` | Product name as shown in the app |
| `mrp` | Maximum retail price, **in paise** |
| `discountPercent` | Discount applied to MRP |
| `availableQuantity` | Units available (capped at 6 in this data) |
| `discountedSellingPrice` | Price after discount, **in paise** |
| `weightInGms` | Pack weight in grams |
| `outOfStock` | Boolean stock flag |
| `quantity` | Units per pack |

## Tools and Technologies

| Tool | Use |
|---|---|
| **PostgreSQL 16** | Data storage, cleaning and analysis |
| **pgAdmin 4** | Running scripts, importing the CSV, exporting results |
| **Microsoft Excel** | Dashboard (tables, PivotCharts, charts) and the restock model |
| **SQL techniques** | CTEs, window functions (`ROW_NUMBER`, `RANK`, `LAG`, running totals), `PERCENTILE_CONT`, `CORR`, `FILTER`, `STRING_AGG`, views |
| **Excel techniques** | Structured tables, `INDEX/MATCH`, `RANK.EQ`, `COUNTIFS`, min-max normalisation, PivotCharts, Pareto combo chart |
| **Git / GitHub** | Version control and portfolio |

## Project Structure

```
zepto-catalog-audit/
├── data/
│   └── zepto_v2.csv                  # Raw dataset (never edited)
├── sql/
│   ├── 01_load.sql                   # Creates zepto_raw and imports the CSV
│   ├── 02_profile.sql                # Row counts, NULL checks, first look
│   ├── 03_clean.sql                  # Builds data_issues, zepto_clean, zepto_products
│   └── 04_analysis.sql               # The 10 business questions (Q1 to Q10)
├── exports/                          # Query results exported as CSV for Excel
│   ├── q01a_catalog.csv
│   ├── q02_oos_by_category.csv
│   ├── q04a_discount_bands.csv
│   ├── q09b_abc_detail.csv
│   ├── q09c_abc_summary.csv
│   ├── q10_restock_candidates.csv
│   └── ...
├── excel/
│   └── zepto_audit.xlsx              # Dashboard, restock model, findings
└── README.md
```

| Database object | Created by | Purpose |
|---|---|---|
| `zepto_raw` | `01_load.sql` | Untouched copy of the CSV (prices in paise) |
| `data_issues` | `03_clean.sql` | Log of every data problem: issue, rows affected, action taken |
| `zepto_clean` | `03_clean.sql` | One row per **listing**, in rupees, trimmed names, duplicates removed |
| `zepto_products` | `03_clean.sql` | One row per **unique product**, with `listing_count` and `category_count` |
| `v_abc` | `04_analysis.sql` | View used for the inventory ABC analysis |

## Loading the Data

Create the raw table. Values stay exactly as in the file (prices as integer paise).

```sql
CREATE TABLE zepto_raw (
  sku_id              SERIAL PRIMARY KEY,
  category            VARCHAR(120),
  name                VARCHAR(150) NOT NULL,
  mrp_paise           INTEGER,
  discount_percent    NUMERIC(5,2),
  available_quantity  INTEGER,
  selling_price_paise INTEGER,
  weight_gms          INTEGER,
  out_of_stock        BOOLEAN,
  quantity            INTEGER
);
```

Import the CSV with pgAdmin's **Import/Export** dialog, or with `\copy`:

```sql
\copy zepto_raw(category,name,mrp_paise,discount_percent,available_quantity,
                selling_price_paise,weight_gms,out_of_stock,quantity)
FROM 'data/zepto_v2.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
```

**Check:** `SELECT COUNT(*) FROM zepto_raw;` returns **3,732**.

## Data Cleaning and Preparation

Cleaning builds new tables from `zepto_raw`; the raw table is never changed.

**Problems found and logged in `data_issues`:**

| Issue | Rows | Action |
|---|---|---|
| MRP or selling price is zero | 1 | Removed from `zepto_clean` |
| Weight is zero | 4 | Kept; excluded from price-per-gram analysis |
| Product name has leading/trailing spaces | 296 | Trimmed |
| Exact duplicate rows (all columns identical) | 2 | Removed with `ROW_NUMBER()` |
| Stated discount differs from the real price gap by more than ₹1 | 408 | Kept and flagged. The gap is never more than 1 percentage point, so the source rounds the discount down; this is a rounding convention, not an error |
| Same product listed under more than one category | 1,281 | Kept in `zepto_clean`; collapsed to one row in `zepto_products` |

**Steps in `03_clean.sql`:**

1. Convert paise to rupees (`/ 100.0`) in the clean layer only.
2. Trim names and remove the zero-price row.
3. Remove exact duplicates, keeping the first occurrence:

```sql
ROW_NUMBER() OVER (
  PARTITION BY category, TRIM(name), mrp_paise, discount_percent, available_quantity,
               selling_price_paise, weight_gms, out_of_stock, quantity
  ORDER BY sku_id) AS rn
-- then keep WHERE rn = 1
```

4. Calculate the real discount (`actual_discount_pct`) and flag mismatches (`discount_gap_flag`).
5. Build `zepto_products` by grouping rows that match on everything except category:

```sql
SELECT MIN(sku_id) AS product_id, name, mrp, selling_price, weight_gms, quantity,
       COUNT(*) AS listing_count,
       COUNT(DISTINCT category) AS category_count,
       STRING_AGG(DISTINCT category, ' | ') AS categories
FROM zepto_clean
GROUP BY name, mrp, discount_percent, selling_price, actual_discount_pct,
         weight_gms, quantity, available_quantity, out_of_stock;
```

**Reconciliation:** 3,732 raw rows → **3,729** listings → **1,800** unique products.

## EDA (Exploratory Data Analysis)

Run in `02_profile.sql` and in the first analysis queries:

| Finding | Result |
|---|---|
| Total rows / categories | 3,732 rows, 14 categories |
| NULL values | None in any column |
| Distinct product names (raw) | 1,674, far fewer than rows, which signalled duplication |
| Out-of-stock rows (raw) | 453 (about 12%) |
| Unique products after cleaning | 1,800 |
| Average listings per product | 2.07 |
| Products appearing in more than one category | 1,281 (71.2%) |
| Most categories for a single product | 7 |
| Categories that are 100% cross-listed copies | 9 of 14 |
| Most reliable category label | Biscuits (0% cross-listed) |
| Available quantity | Capped at 6 (1,620 rows show exactly 6) |

**Example:** *Arden Eggs White* is only 2 products (a 12-egg pack and a 6-egg pack), but it appears as 10 listings across 5 categories, including Beverages and Munchies. Category labels in this dataset are therefore partly unreliable, and every category-level result is read with that in mind.

## SQL Business Analysis

All ten queries are in `sql/04_analysis.sql`. Each states which table it uses (listings or unique products) and why.

| # | Business question | Key technique | Key result |
|---|---|---|---|
| Q1 | How inflated is the catalog? | Subquery, `FILTER`, join | 71.2% of products are cross-listed |
| Q2 | Which categories run out of stock most, and is the label reliable? | CTE, `CROSS JOIN`, `RANK` | Biscuits: 28.6% out of stock vs about 12.2% overall |
| Q3 | Which heavily discounted (20%+) products are out of stock? | Filtering on unique products | 9 products, four of them at 50% off |
| Q4 | How deep are discounts? | `CASE` bands, `SUM(COUNT(*)) OVER ()` | 29.8% no discount, 47.3% at 1-10%; about 77% at 10% or less |
| Q5 | Do pricier products get smaller discounts? | Median (`PERCENTILE_CONT`), `CORR` | Not a straight line; negative correlation only in Fruits & Vegetables (-0.31) |
| Q6 | Do the best percentage deals save the most rupees? | Two `RANK()` columns | Borges Extra Light Olive Oil saves ₹1,201 (46% off) yet ranks 23rd by percentage |
| Q7 | Best and worst value per 100g within a category | Chained CTEs, `ROW_NUMBER ... PARTITION BY` | Aashirvaad Iodised Salt is 0.07x its category median price per 100g |
| Q8 | Is a bigger pack really cheaper per 100g? | `LAG()` over a named `WINDOW` | 29 of 101 size comparisons: the bigger pack costs more |
| Q9 | Where is stock value concentrated? | Running total, view, ABC classes | 531 products (33.5%) hold 70% of stock value |
| Q10 | Which out-of-stock products should be restocked first? | Raw signals exported for scoring | 217 candidates, scored in Excel |

**Example query (Q8, pack-size ladder):**

```sql
WITH sizes AS (
  SELECT name, weight_gms, MIN(selling_price) AS price
  FROM zepto_products WHERE weight_gms >= 50
  GROUP BY name, weight_gms
),
ladder AS (
  SELECT name, weight_gms,
         ROUND(price * 100.0 / weight_gms, 2) AS price_per_100g,
         LAG(weight_gms) OVER w AS prev_weight,
         LAG(ROUND(price * 100.0 / weight_gms, 2)) OVER w AS prev_price_per_100g
  FROM sizes
  WINDOW w AS (PARTITION BY name ORDER BY weight_gms)
)
SELECT name, prev_weight, weight_gms, prev_price_per_100g, price_per_100g,
       CASE WHEN price_per_100g < prev_price_per_100g THEN 'Bigger pack cheaper'
            WHEN price_per_100g = prev_price_per_100g THEN 'Same rate'
            ELSE 'Bigger pack costs MORE' END AS verdict
FROM ladder
WHERE prev_weight IS NOT NULL;
```

## Dashboard

The query results are exported from pgAdmin as CSV files and loaded into **Microsoft Excel**, where they feed a one-page dashboard. It covers catalog size and availability, discount depth, the pack-size pricing check, stock-value concentration (ABC / Pareto), and a live Top 10 restock list.

**Restock model (Excel):** each out-of-stock product gets a priority score from three min-max-normalised signals: discount depth (promoted demand), selling price (revenue per sale) and listing count (visibility). The default weights are 40% / 30% / 30% and can be changed in three input cells; the Top 20 list updates instantly. Products that stay near the top under different weightings are the most confident restock picks.

## Results and Conclusion

**Key findings**

1. **The catalog is about twice as large as its real product list.** 3,729 listings represent only 1,800 products; 71.2% of products appear in more than one category, so category-level metrics are inflated.
2. **Biscuits has the clearest availability problem.** 28.6% of its listings are out of stock, 16.4 percentage points above the overall rate (about 12.2%), and its category label is clean.
3. **Promotions are being wasted.** Nine products discounted 20% or more are out of stock.
4. **Discounts are shallow and uneven.** About 30% of products have no discount and about 77% have 10% or less. The average discount does not rise steadily with price.
5. **Percentage discounts mislead.** The biggest rupee savings (such as the olive oil at ₹1,201 off) are not the biggest percentage discounts.
6. **"Buy bigger to save" is not always true.** In 29 of 101 pack-size comparisons, the larger pack costs more per 100g.
7. **A third of products carry most of the stock value.** 531 Class A products (33.5%) hold 70% of the in-stock value index.

**Recommendations**

- **Fix catalog hygiene first:** de-duplicate cross-listed products and correct category assignments so category reporting can be trusted.
- **Restock promoted items:** prioritise the nine heavily discounted out-of-stock products and the top of the restock model's ranking.
- **Review Biscuits supply:** investigate why availability is so much worse than the overall rate.
- **Audit pack pricing:** review the 29 cases where larger packs cost more per 100g.
- **Protect Class A availability:** these products drive most of the stock value.

## Limitations

- **Category labels are partly duplicated,** so category-level results are caveated (Q2 includes a label-reliability column).
- **Available quantity is capped at 6,** so stock value is an index, not true inventory value.
- **No cost or sales data,** so margins and lost revenue cannot be calculated.
- **Single snapshot,** so trends over time are not visible.
- **Restock weights are a judgement,** not a fact; they are adjustable by design.

## How to Run

1. Clone the repository:
   ```bash
   git clone https://github.com/Vipparti-Vinay/zepto-catalog-audit.git
   cd zepto-catalog-audit
   ```
2. In PostgreSQL, create a database named `zepto_db`.
3. Run the scripts in order in pgAdmin's Query Tool: `01_load.sql` → `02_profile.sql` → `03_clean.sql` → `04_analysis.sql`. (Update the file path in `01_load.sql` if you use `\copy`.)
4. Confirm the checkpoints: **3,732** raw rows → **3,729** clean listings → **1,800** unique products.
5. Export each query result to `exports/` as CSV, then open `excel/zepto_audit.xlsx` (or rebuild it by importing the CSVs with **Data → From Text/CSV**, UTF-8).

## Author and Contact

**Vipparti Vinay**

- Email: [vinayvipparti.in@gmail.com](mailto:vinayvipparti.in@gmail.com)
- LinkedIn: [linkedin.com/in/vipparti-vinay](https://www.linkedin.com/in/vipparti-vinay)
- GitHub: [github.com/Vipparti-Vinay](https://github.com/Vipparti-Vinay)
