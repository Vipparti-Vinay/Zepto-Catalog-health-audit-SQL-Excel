-- Q1a. How inflated is the catalog?
SELECT (SELECT COUNT(*) FROM zepto_clean)                              AS total_listings,
       COUNT(*)                                                        AS unique_products,
       ROUND(SUM(listing_count)::NUMERIC / COUNT(*), 2)                AS avg_listings_per_product,
       COUNT(*) FILTER (WHERE category_count > 1)                      AS products_in_multiple_categories,
       ROUND(100.0 * COUNT(*) FILTER (WHERE category_count > 1) / COUNT(*), 1) AS pct_multi_category,
       MAX(category_count)                                             AS max_categories_one_product
FROM zepto_products;

-- Q1b. Per category: how many listings are copies of a product that also appears elsewhere?
SELECT c.category,
       COUNT(*)                                             AS listings,
       COUNT(*) FILTER (WHERE p.category_count > 1)         AS cross_listed,
       ROUND(100.0 * COUNT(*) FILTER (WHERE p.category_count > 1) / COUNT(*), 1) AS pct_cross_listed
FROM zepto_clean c
JOIN zepto_products p USING (product_id)
GROUP BY c.category
ORDER BY pct_cross_listed DESC;

-- Q2. Out-of-stock rate by category vs the overall rate, with a label-reliability check
WITH overall AS (
  SELECT 100.0 * COUNT(*) FILTER (WHERE out_of_stock) / COUNT(*) AS overall_oos_pct
  FROM zepto_clean
)
SELECT c.category,
       COUNT(*)                                                            AS listings,
       COUNT(*) FILTER (WHERE c.out_of_stock)                              AS oos_listings,
       ROUND(100.0 * COUNT(*) FILTER (WHERE c.out_of_stock) / COUNT(*), 1) AS oos_pct,
       ROUND(100.0 * COUNT(*) FILTER (WHERE c.out_of_stock) / COUNT(*) - o.overall_oos_pct, 1) AS pp_vs_overall,
       RANK() OVER (ORDER BY COUNT(*) FILTER (WHERE c.out_of_stock)::NUMERIC / COUNT(*) DESC) AS worst_rank,
       ROUND(100.0 * COUNT(*) FILTER (WHERE p.category_count > 1) / COUNT(*), 1) AS pct_cross_listed,
       CASE WHEN 100.0 * COUNT(*) FILTER (WHERE p.category_count > 1) / COUNT(*) < 10 THEN 'Reliable label'
            WHEN 100.0 * COUNT(*) FILTER (WHERE p.category_count > 1) / COUNT(*) < 60 THEN 'Mixed'
            ELSE 'Heavily duplicated' END AS label_quality
FROM zepto_clean c
JOIN zepto_products p USING (product_id)
CROSS JOIN overall o
GROUP BY c.category, o.overall_oos_pct
ORDER BY oos_pct DESC;

-- Q3. Heavily discounted products (20%+) that are out of stock
SELECT name, mrp, selling_price, discount_percent, listing_count, categories
FROM zepto_products
WHERE out_of_stock AND discount_percent >= 20
ORDER BY discount_percent DESC, listing_count DESC, mrp DESC;

-- Q4a. How deep are discounts overall? (unique products)
SELECT CASE WHEN discount_percent = 0   THEN '1. No discount'
            WHEN discount_percent <= 10 THEN '2. 1-10%'
            WHEN discount_percent <= 20 THEN '3. 11-20%'
            WHEN discount_percent <= 30 THEN '4. 21-30%'
            ELSE '5. Above 30%' END AS discount_band,
       COUNT(*) AS products,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct_of_products
FROM zepto_products
GROUP BY 1
ORDER BY 1;

-- Q4b. Same bands by category (long format, ready for an Excel PivotTable)
SELECT category,
       CASE WHEN discount_percent = 0   THEN '1. No discount'
            WHEN discount_percent <= 10 THEN '2. 1-10%'
            WHEN discount_percent <= 20 THEN '3. 11-20%'
            WHEN discount_percent <= 30 THEN '4. 21-30%'
            ELSE '5. Above 30%' END AS discount_band,
       COUNT(*) AS listings
FROM zepto_clean
GROUP BY 1, 2
ORDER BY 1, 2;

-- Q5a. Do pricier products get smaller discounts? (unique products)
SELECT CASE WHEN mrp < 100  THEN '1. Under Rs100'
            WHEN mrp < 250  THEN '2. Rs100-249'
            WHEN mrp < 500  THEN '3. Rs250-499'
            WHEN mrp < 1000 THEN '4. Rs500-999'
            ELSE '5. Rs1000+' END AS price_band,
       COUNT(*)                                                         AS products,
       ROUND(AVG(discount_percent), 1)                                  AS avg_discount_pct,
       PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY discount_percent)    AS median_discount_pct,
       ROUND(100.0 * COUNT(*) FILTER (WHERE discount_percent = 0) / COUNT(*), 1) AS pct_with_no_discount
FROM zepto_products
GROUP BY 1
ORDER BY 1;

-- Q5b. Strength of the MRP vs discount relationship, per category (listing level)
SELECT category,
       COUNT(*) AS listings,
       ROUND(CORR(mrp, discount_percent)::NUMERIC, 2) AS corr_mrp_discount
FROM zepto_clean
GROUP BY category
HAVING COUNT(*) >= 30
ORDER BY corr_mrp_discount;

-- Q6. Best deals: % discount vs rupees actually saved (in-stock unique products)
WITH deals AS (
  SELECT name, mrp, selling_price, discount_percent,
         ROUND(mrp - selling_price, 2) AS rupees_saved,
         weight_gms, listing_count
  FROM zepto_products
  WHERE NOT out_of_stock
),
ranked AS (
  SELECT *,
         RANK() OVER (ORDER BY discount_percent DESC) AS pct_rank,
         RANK() OVER (ORDER BY rupees_saved DESC)     AS rupee_rank
  FROM deals
)
SELECT name, mrp, selling_price, discount_percent, rupees_saved,
       pct_rank, rupee_rank, (pct_rank - rupee_rank) AS rank_jump
FROM ranked
WHERE rupee_rank <= 25
ORDER BY rupee_rank;

-- Q7. Value for money inside each category: price per 100g vs the category median
WITH base AS (
  SELECT category, name, weight_gms, selling_price,
         ROUND(selling_price * 100.0 / weight_gms, 2) AS price_per_100g
  FROM zepto_clean
  WHERE weight_gms >= 100
),
med AS (
  SELECT category,
         ROUND((PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY price_per_100g))::NUMERIC, 2) AS median_per_100g
  FROM base
  GROUP BY category
),
ranked AS (
  SELECT b.*, m.median_per_100g,
         ROUND(b.price_per_100g / NULLIF(m.median_per_100g, 0), 2) AS x_vs_median,
         ROW_NUMBER() OVER (PARTITION BY b.category ORDER BY b.price_per_100g ASC,  b.name) AS cheapest_rank,
         ROW_NUMBER() OVER (PARTITION BY b.category ORDER BY b.price_per_100g DESC, b.name) AS priciest_rank
  FROM base b
  JOIN med m USING (category)
)
SELECT category, name, weight_gms, selling_price, price_per_100g, median_per_100g, x_vs_median,
       CASE WHEN cheapest_rank <= 3 THEN 'Cheapest 3' ELSE 'Priciest 3' END AS tag
FROM ranked
WHERE cheapest_rank <= 3 OR priciest_rank <= 3
ORDER BY category, price_per_100g;

-- Q8. Pack-size ladder: does a bigger pack cost less per 100g?
WITH sizes AS (
  SELECT name, weight_gms, MIN(selling_price) AS price
  FROM zepto_products
  WHERE weight_gms >= 50
  GROUP BY name, weight_gms
),
ladder AS (
  SELECT name, weight_gms, price,
         ROUND(price * 100.0 / weight_gms, 2) AS price_per_100g,
         LAG(weight_gms) OVER w AS prev_weight,
         LAG(ROUND(price * 100.0 / weight_gms, 2)) OVER w AS prev_price_per_100g
  FROM sizes
  WINDOW w AS (PARTITION BY name ORDER BY weight_gms)
)
SELECT name, prev_weight AS from_weight_g, weight_gms AS to_weight_g,
       prev_price_per_100g, price_per_100g,
       ROUND((price_per_100g - prev_price_per_100g) * 100.0 / prev_price_per_100g, 1) AS change_pct,
       CASE WHEN price_per_100g < prev_price_per_100g THEN 'Bigger pack cheaper'
            WHEN price_per_100g = prev_price_per_100g THEN 'Same rate'
            ELSE 'Bigger pack costs MORE' END AS verdict
FROM ladder
WHERE prev_weight IS NOT NULL
ORDER BY change_pct DESC;

-- Q9a. Create a view that ranks every in-stock unique product by stock value (ABC analysis)
CREATE OR REPLACE VIEW v_abc AS
WITH stock AS (
  SELECT product_id, name, selling_price, available_quantity,
         selling_price * available_quantity AS stock_value
  FROM zepto_products
  WHERE NOT out_of_stock
),
cum AS (
  SELECT *,
         ROW_NUMBER() OVER (ORDER BY stock_value DESC, product_id) AS value_rank,
         100.0 * SUM(stock_value) OVER (ORDER BY stock_value DESC, product_id)
               / SUM(stock_value) OVER () AS cumulative_pct
  FROM stock
)
SELECT product_id, name, selling_price, available_quantity, stock_value, value_rank,
       ROUND(cumulative_pct, 1) AS cumulative_pct,
       CASE WHEN cumulative_pct <= 70 THEN 'A'
            WHEN cumulative_pct <= 90 THEN 'B'
            ELSE 'C' END AS abc_class
FROM cum;

-- Q9b. Detail table (export this one for the Excel Pareto chart)
SELECT * FROM v_abc ORDER BY value_rank;

-- Q9c. ABC summary
SELECT abc_class,
       COUNT(*)                                                           AS products,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1)                 AS pct_of_products,
       SUM(stock_value)                                                   AS stock_value,
       ROUND(100.0 * SUM(stock_value) / SUM(SUM(stock_value)) OVER (), 1) AS pct_of_value
FROM v_abc
GROUP BY abc_class
ORDER BY abc_class;

-- Q10. Restock candidates: every out-of-stock unique product with the raw signals (scoring happens in Excel)
SELECT product_id, name, categories, mrp, selling_price, discount_percent,
       listing_count, category_count, weight_gms
FROM zepto_products
WHERE out_of_stock
ORDER BY discount_percent DESC, mrp DESC;