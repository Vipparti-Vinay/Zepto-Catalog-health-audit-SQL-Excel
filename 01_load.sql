--loading the data

DROP TABLE IF EXISTS zepto_raw;
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

--verify the load
SELECT COUNT(*) FROM zepto_raw;

