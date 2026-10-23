DROP TABLE IF EXISTS data_issues;
CREATE TABLE data_issues (
  issue        TEXT,
  rows_found   INTEGER,
  action_taken TEXT
);

INSERT INTO data_issues
SELECT 'MRP or selling price is zero', COUNT(*), 'Removed from zepto_clean'
FROM zepto_raw WHERE mrp_paise = 0 OR selling_price_paise = 0;

INSERT INTO data_issues
SELECT 'Weight is zero', COUNT(*), 'Kept; excluded from price-per-gram analysis'
FROM zepto_raw WHERE weight_gms = 0;

INSERT INTO data_issues
SELECT 'Name has leading/trailing spaces', COUNT(*), 'Trimmed in zepto_clean'
FROM zepto_raw WHERE name <> TRIM(name);

INSERT INTO data_issues
SELECT 'Exact duplicate rows (all columns identical)', COUNT(*) - COUNT(DISTINCT (category, TRIM(name), mrp_paise, discount_percent, available_quantity, selling_price_paise, weight_gms, out_of_stock, quantity)), 'Removed from zepto_clean'
FROM zepto_raw;

INSERT INTO data_issues
SELECT 'Stated discount differs from real discount by more than 1 rupee', COUNT(*), 'Kept; flagged in zepto_clean.discount_gap_flag'
FROM zepto_raw
WHERE mrp_paise > 0 AND ABS(mrp_paise * (1 - discount_percent/100.0) - selling_price_paise) > 100;

DROP TABLE IF EXISTS zepto_clean CASCADE;
CREATE TABLE zepto_clean AS
WITH numbered AS (
  SELECT r.*,
         ROW_NUMBER() OVER (
           PARTITION BY category, TRIM(name), mrp_paise, discount_percent, available_quantity,
                        selling_price_paise, weight_gms, out_of_stock, quantity
           ORDER BY sku_id) AS rn
  FROM zepto_raw r
  WHERE mrp_paise > 0 AND selling_price_paise > 0
)
SELECT sku_id,
       category,
       TRIM(name)                                   AS name,
       ROUND(mrp_paise / 100.0, 2)                  AS mrp,
       discount_percent,
       ROUND(selling_price_paise / 100.0, 2)        AS selling_price,
       ROUND((mrp_paise - selling_price_paise) * 100.0 / mrp_paise, 1) AS actual_discount_pct,
       (ABS(mrp_paise * (1 - discount_percent/100.0) - selling_price_paise) > 100) AS discount_gap_flag,
       available_quantity,
       weight_gms,
       out_of_stock,
       quantity
FROM numbered
WHERE rn = 1;

ALTER TABLE zepto_clean ADD PRIMARY KEY (sku_id);

DROP TABLE IF EXISTS zepto_products CASCADE;
CREATE TABLE zepto_products AS
SELECT MIN(sku_id)                          AS product_id,
       name, mrp, discount_percent, selling_price, actual_discount_pct,
       weight_gms, quantity, available_quantity, out_of_stock,
       COUNT(*)                             AS listing_count,
       COUNT(DISTINCT category)             AS category_count,
       STRING_AGG(DISTINCT category, ' | ') AS categories
FROM zepto_clean
GROUP BY name, mrp, discount_percent, selling_price, actual_discount_pct,
         weight_gms, quantity, available_quantity, out_of_stock;

ALTER TABLE zepto_products ADD PRIMARY KEY (product_id);


ALTER TABLE zepto_clean ADD COLUMN product_id INTEGER;
UPDATE zepto_clean c
SET product_id = p.product_id
FROM zepto_products p
WHERE c.name = p.name AND c.mrp = p.mrp AND c.discount_percent = p.discount_percent
  AND c.selling_price = p.selling_price AND c.weight_gms = p.weight_gms
  AND c.quantity = p.quantity AND c.available_quantity = p.available_quantity
  AND c.out_of_stock = p.out_of_stock;

INSERT INTO data_issues
SELECT 'Same product listed under more than one category', COUNT(*), 'Kept in zepto_clean; collapsed to one row in zepto_products'
FROM zepto_products WHERE category_count > 1;

SELECT * FROM data_issues;
SELECT (SELECT COUNT(*) FROM zepto_raw) raw_rows, (SELECT COUNT(*) FROM zepto_clean) clean_rows, (SELECT COUNT(*) FROM zepto_products) product_rows;