SELECT COUNT(*) AS total_rows,
       COUNT(DISTINCT category) AS categories,
       COUNT(DISTINCT TRIM(name)) AS distinct_names,
       SUM(CASE WHEN out_of_stock THEN 1 ELSE 0 END) AS out_of_stock_rows
FROM zepto_raw;

SELECT
  COUNT(*) FILTER (WHERE category IS NULL)            AS null_category,
  COUNT(*) FILTER (WHERE mrp_paise IS NULL)           AS null_mrp,
  COUNT(*) FILTER (WHERE discount_percent IS NULL)    AS null_discount,
  COUNT(*) FILTER (WHERE selling_price_paise IS NULL) AS null_price,
  COUNT(*) FILTER (WHERE weight_gms IS NULL)          AS null_weight,
  COUNT(*) FILTER (WHERE available_quantity IS NULL)  AS null_qty,
  COUNT(*) FILTER (WHERE out_of_stock IS NULL)        AS null_oos
FROM zepto_raw;