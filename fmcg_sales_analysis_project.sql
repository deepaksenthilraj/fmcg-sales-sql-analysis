/* =====================================================================
   PROJECT: FMCG Retail Sales Analysis (PostgreSQL)
   ---------------------------------------------------------------------
   Business story:
   A packaged-goods company sells 12 products (tea, snacks, personal care,
   household) through 10 stores in Chennai, Coimbatore, Bengaluru and
   Hyderabad during 2025. The data has a few deliberate quality problems.
   Your job: audit the data, clean it, then answer business questions.

   HOW TO RUN (pgAdmin):
   1. Create an empty database called fmcg_project, open Query Tool.
   2. PART 1: select the whole Part 1 block and press F5. Run it ONCE.
   3. Every other query: highlight ONE query at a time and press F5.
      (pgAdmin only shows the result of the last statement it runs.)
   ===================================================================== */


/* =====================================================================
   PART 1 - SETUP: tables and practice data
   Run this whole part once. You do not need to memorise the data
   generator; it only creates practice rows.
   ===================================================================== */

DROP VIEW  IF EXISTS sales_enriched;
DROP TABLE IF EXISTS sales_clean;
DROP TABLE IF EXISTS sales;
DROP TABLE IF EXISTS products;
DROP TABLE IF EXISTS stores;

CREATE TABLE products (
    product_id   SERIAL PRIMARY KEY,
    product_name VARCHAR(100)  NOT NULL,
    brand        VARCHAR(50)   NOT NULL,
    category     VARCHAR(50)   NOT NULL,
    unit_price   NUMERIC(8,2)  NOT NULL
);

CREATE TABLE stores (
    store_id   SERIAL PRIMARY KEY,
    store_name VARCHAR(100) NOT NULL,
    city       VARCHAR(50)  NOT NULL,
    channel    VARCHAR(30)  NOT NULL      -- Supermarket, Kirana or Online
);

CREATE TABLE sales (
    sale_id      SERIAL PRIMARY KEY,
    sale_date    DATE NOT NULL,
    store_id     INT  NOT NULL REFERENCES stores(store_id),
    product_id   INT  NOT NULL REFERENCES products(product_id),
    units_sold   INT,                     -- nullable on purpose (dirty data)
    discount_pct NUMERIC(4,1) DEFAULT 0
);

INSERT INTO products (product_name, brand, category, unit_price) VALUES
('Masala Tea 250g',        'ChaiKing',    'Beverages',     120.00),
('Instant Coffee 100g',    'BrewMate',    'Beverages',     210.00),
('Fruit Juice 1L',         'FreshSip',    'Beverages',      95.00),
('Potato Chips 150g',      'CrunchCo',    'Snacks',         50.00),
('Salted Biscuits 200g',   'BiscoBite',   'Snacks',         35.00),
('Namkeen Mix 400g',       'CrunchCo',    'Snacks',        110.00),
('Herbal Shampoo 340ml',   'LeafCare',    'Personal Care', 245.00),
('Bath Soap 4-pack',       'PureGlow',    'Personal Care', 160.00),
('Toothpaste 200g',        'BrightSmile', 'Personal Care', 115.00),
('Dishwash Liquid 500ml',  'SparkleHome', 'Household',      99.00),
('Floor Cleaner 1L',       'SparkleHome', 'Household',     185.00),
('Laundry Detergent 1kg',  'WashWell',    'Household',     130.00);

INSERT INTO stores (store_name, city, channel) VALUES
('Metro Fresh - T Nagar',        'Chennai',    'Supermarket'),
('Metro Fresh - Anna Nagar',     'Chennai',    'Supermarket'),
('Kumar Kirana',                 'Chennai',    'Kirana'),
('GreenBasket - RS Puram',       'Coimbatore', 'Supermarket'),
('Lakshmi Stores',               'Coimbatore', 'Kirana'),
('Metro Fresh - Indiranagar',    'Bengaluru',  'Supermarket'),
('QuickCart Online - Bengaluru', 'Bengaluru',  'Online'),
('QuickCart Online - Chennai',   'Chennai',    'Online'),
('Sharma General Store',         'Hyderabad',  'Kirana'),
('GreenBasket - Banjara Hills',  'Hyderabad',  'Supermarket');

-- Practice data: about 5,000 sales rows for 2025.
-- Built-in patterns to discover later: higher sales in Oct-Dec (festive
-- season) and more units sold when the discount is higher.
INSERT INTO sales (sale_date, store_id, product_id, units_sold, discount_pct)
SELECT sale_date, store_id, product_id,
       base_units
         + CASE WHEN EXTRACT(MONTH FROM sale_date) >= 10 THEN 15 ELSE 0 END
         + discount_pct::int,
       discount_pct
FROM (
    SELECT DATE '2025-01-01' + d                         AS sale_date,
           st.store_id,
           p.product_id,
           (1 + floor(random() * 40))::int               AS base_units,
           (ARRAY[0,0,0,5,10,15])[1 + floor(random() * 6)::int] AS discount_pct
    FROM generate_series(0, 364) AS d
    CROSS JOIN stores   st
    CROSS JOIN products p
    WHERE random() < 0.12
) AS raw;

-- Plant data quality problems (typical of real data operations work):
-- 10 duplicated rows
INSERT INTO sales (sale_date, store_id, product_id, units_sold, discount_pct)
SELECT sale_date, store_id, product_id, units_sold, discount_pct
FROM sales
ORDER BY random()
LIMIT 10;

-- 15 rows with missing units
UPDATE sales
SET units_sold = NULL
WHERE sale_id IN (SELECT sale_id FROM sales ORDER BY random() LIMIT 15);

-- A new store that opened but has no sales yet (used in a LEFT JOIN example)
INSERT INTO stores (store_name, city, channel)
VALUES ('New Store - Madurai', 'Madurai', 'Supermarket');


/* =====================================================================
   PART 2 - SQL BASICS (get comfortable looking at data)
   ===================================================================== */

-- 2.1 Look at the data. LIMIT keeps the output small.
SELECT * FROM products;
SELECT * FROM sales LIMIT 10;

-- 2.2 How many rows are in each table?
SELECT COUNT(*) AS total_sales_rows FROM sales;

-- 2.3 Filter and sort: products priced above 100, most expensive first
SELECT product_name, brand, unit_price
FROM products
WHERE unit_price > 100
ORDER BY unit_price DESC;

-- 2.4 DISTINCT: which categories do we sell?
SELECT DISTINCT category FROM products ORDER BY category;


/* =====================================================================
   PART 3 - DATA QUALITY AUDIT (your real-world strength: say this in
   the interview, it is what you do at work in Excel, now done in SQL)
   ===================================================================== */

-- 3.1 Missing values
SELECT COUNT(*) AS rows_with_missing_units
FROM sales
WHERE units_sold IS NULL;

-- 3.2 Duplicates: the same date + store + product should appear only once
SELECT sale_date, store_id, product_id, COUNT(*) AS times_seen
FROM sales
GROUP BY sale_date, store_id, product_id
HAVING COUNT(*) > 1
ORDER BY times_seen DESC;

-- 3.3 Date range sanity check
SELECT MIN(sale_date) AS first_sale, MAX(sale_date) AS last_sale FROM sales;


/* =====================================================================
   PART 4 - CLEANING: build a clean table and a reporting view
   ===================================================================== */

-- 4.1 sales_clean = no missing units, no duplicates.
-- ROW_NUMBER numbers the copies of each (date, store, product) group.
-- We keep only copy number 1. This is a classic interview question:
-- "How do you remove duplicates in SQL?"
CREATE TABLE sales_clean AS
SELECT sale_id, sale_date, store_id, product_id, units_sold, discount_pct
FROM (
    SELECT *,
           ROW_NUMBER() OVER (
               PARTITION BY sale_date, store_id, product_id
               ORDER BY sale_id
           ) AS rn
    FROM sales
    WHERE units_sold IS NOT NULL
) AS numbered
WHERE rn = 1;

ALTER TABLE sales_clean ADD PRIMARY KEY (sale_id);
CREATE INDEX idx_sales_clean_date ON sales_clean (sale_date);

-- 4.2 Reconcile: how many rows did cleaning remove?
SELECT (SELECT COUNT(*) FROM sales)       AS raw_rows,
       (SELECT COUNT(*) FROM sales_clean) AS clean_rows,
       (SELECT COUNT(*) FROM sales) - (SELECT COUNT(*) FROM sales_clean) AS rows_removed;

-- 4.3 A view joins the three tables once, so every report below is short.
-- revenue = units x price x (1 - discount)
CREATE VIEW sales_enriched AS
SELECT sc.sale_id,
       sc.sale_date,
       st.store_name,
       st.city,
       st.channel,
       p.product_name,
       p.brand,
       p.category,
       sc.units_sold,
       sc.discount_pct,
       sc.units_sold * p.unit_price * (1 - sc.discount_pct / 100) AS revenue
FROM sales_clean sc
JOIN stores   st ON st.store_id   = sc.store_id
JOIN products p  ON p.product_id  = sc.product_id;


/* =====================================================================
   PART 5 - BUSINESS QUESTIONS (GROUP BY, HAVING, JOIN)
   ===================================================================== */

-- 5.1 Total revenue and units
SELECT ROUND(SUM(revenue), 2) AS total_revenue,
       SUM(units_sold)        AS total_units
FROM sales_enriched;

-- 5.2 Revenue by category
SELECT category,
       ROUND(SUM(revenue), 2) AS revenue,
       SUM(units_sold)        AS units
FROM sales_enriched
GROUP BY category
ORDER BY revenue DESC;

-- 5.3 Top 5 products by revenue
SELECT product_name, brand, ROUND(SUM(revenue), 2) AS revenue
FROM sales_enriched
GROUP BY product_name, brand
ORDER BY revenue DESC
LIMIT 5;

-- 5.4 Revenue by city and channel
SELECT city, channel, ROUND(SUM(revenue), 2) AS revenue
FROM sales_enriched
GROUP BY city, channel
ORDER BY city, revenue DESC;

-- 5.5 HAVING filters AFTER grouping (WHERE filters BEFORE grouping).
-- Brands with more than 2,500,000 in revenue.
SELECT brand, ROUND(SUM(revenue), 2) AS revenue
FROM sales_enriched
GROUP BY brand
HAVING SUM(revenue) > 2500000
ORDER BY revenue DESC;

-- 5.6 LEFT JOIN: stores with no sales at all.
-- (INNER JOIN would hide them; LEFT JOIN keeps every store.)
SELECT st.store_name, st.city
FROM stores st
LEFT JOIN sales_clean sc ON sc.store_id = st.store_id
WHERE sc.sale_id IS NULL;

-- 5.7 Does discounting work? Average units per sale by discount level.
SELECT discount_pct,
       COUNT(*)                  AS transactions,
       ROUND(AVG(units_sold), 1) AS avg_units_per_sale
FROM sales_enriched
GROUP BY discount_pct
ORDER BY discount_pct;


/* =====================================================================
   PART 6 - ADVANCED: CTEs and WINDOW FUNCTIONS
   (This is what separates "knows SQL" from "knows basic SQL")
   ===================================================================== */

-- 6.1 Monthly revenue with month-over-month growth.
-- A CTE (WITH ...) is a named temporary result, easier to read than
-- a subquery. LAG looks at the previous row.
WITH monthly AS (
    SELECT TO_CHAR(sale_date, 'YYYY-MM') AS month,
           SUM(revenue)                  AS revenue
    FROM sales_enriched
    GROUP BY TO_CHAR(sale_date, 'YYYY-MM')
)
SELECT month,
       ROUND(revenue, 2) AS revenue,
       ROUND(100.0 * (revenue - LAG(revenue) OVER (ORDER BY month))
             / LAG(revenue) OVER (ORDER BY month), 1) AS mom_growth_pct
FROM monthly
ORDER BY month;

-- 6.2 Running (cumulative) revenue by month
WITH monthly AS (
    SELECT TO_CHAR(sale_date, 'YYYY-MM') AS month,
           SUM(revenue)                  AS revenue
    FROM sales_enriched
    GROUP BY TO_CHAR(sale_date, 'YYYY-MM')
)
SELECT month,
       ROUND(revenue, 2)                                 AS revenue,
       ROUND(SUM(revenue) OVER (ORDER BY month), 2)      AS running_total
FROM monthly
ORDER BY month;

-- 6.3 Rank products inside each category (RANK + PARTITION BY)
WITH product_rev AS (
    SELECT category, product_name, SUM(revenue) AS revenue
    FROM sales_enriched
    GROUP BY category, product_name
)
SELECT category,
       product_name,
       ROUND(revenue, 2) AS revenue,
       RANK() OVER (PARTITION BY category ORDER BY revenue DESC) AS rank_in_category
FROM product_rev
ORDER BY category, rank_in_category;

-- 6.4 Brand share of total revenue (a window over the whole result)
SELECT brand,
       ROUND(SUM(revenue), 2) AS revenue,
       ROUND(100.0 * SUM(revenue) / SUM(SUM(revenue)) OVER (), 1) AS share_pct
FROM sales_enriched
GROUP BY brand
ORDER BY share_pct DESC;

-- 6.5 Best-selling product in each city (ROW_NUMBER, keep rank 1)
WITH city_product AS (
    SELECT city, product_name, SUM(units_sold) AS units
    FROM sales_enriched
    GROUP BY city, product_name
),
ranked AS (
    SELECT *,
           ROW_NUMBER() OVER (PARTITION BY city ORDER BY units DESC) AS rn
    FROM city_product
)
SELECT city, product_name, units
FROM ranked
WHERE rn = 1
ORDER BY city;

-- 6.6 Stores performing below the average store (subquery inside a CTE)
WITH store_rev AS (
    SELECT store_name, city, SUM(revenue) AS revenue
    FROM sales_enriched
    GROUP BY store_name, city
)
SELECT store_name,
       city,
       ROUND(revenue, 2) AS revenue,
       ROUND((SELECT AVG(revenue) FROM store_rev), 2) AS avg_store_revenue
FROM store_rev
WHERE revenue < (SELECT AVG(revenue) FROM store_rev)
ORDER BY revenue;
