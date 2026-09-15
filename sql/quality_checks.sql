-- Read-only checks after CALL public.refresh_warehouse().
-- Counts are informational; zero-row violation results alone do not prove a load.
SELECT 'bronze' AS layer, 'customers' AS entity, COUNT(*) AS rows FROM bronze.customers
UNION ALL SELECT 'bronze','employees',COUNT(*) FROM bronze.employees
UNION ALL SELECT 'bronze','products',COUNT(*) FROM bronze.products
UNION ALL SELECT 'bronze','stores',COUNT(*) FROM bronze.stores
UNION ALL SELECT 'bronze','orders',COUNT(*) FROM bronze.orders
UNION ALL SELECT 'bronze','order_items',COUNT(*) FROM bronze.order_items
UNION ALL SELECT 'silver','customers',COUNT(*) FROM silver.customers
UNION ALL SELECT 'silver','employees',COUNT(*) FROM silver.employees
UNION ALL SELECT 'silver','products',COUNT(*) FROM silver.products
UNION ALL SELECT 'silver','stores',COUNT(*) FROM silver.stores
UNION ALL SELECT 'silver','orders',COUNT(*) FROM silver.orders
UNION ALL SELECT 'silver','order_items',COUNT(*) FROM silver.order_items
UNION ALL SELECT 'gold','dim_customers',COUNT(*) FROM gold.dim_customers
UNION ALL SELECT 'gold','dim_employees',COUNT(*) FROM gold.dim_employees
UNION ALL SELECT 'gold','dim_products',COUNT(*) FROM gold.dim_products
UNION ALL SELECT 'gold','dim_stores',COUNT(*) FROM gold.dim_stores
UNION ALL SELECT 'gold','dim_date',COUNT(*) FROM gold.dim_date
UNION ALL SELECT 'gold','fact_sales',COUNT(*) FROM gold.fact_sales
ORDER BY 1,2;

-- Expected: zero rows for the following violation queries.
SELECT order_item_id, COUNT(*) FROM gold.fact_sales
GROUP BY order_item_id HAVING COUNT(*) > 1;

SELECT i.order_item_id AS silver_item, f.order_item_id AS gold_item
FROM silver.order_items i FULL JOIN gold.fact_sales f USING (order_item_id)
WHERE i.order_item_id IS NULL OR f.order_item_id IS NULL;

SELECT f.order_item_id FROM gold.fact_sales f
LEFT JOIN gold.dim_customers c USING (customer_sk)
LEFT JOIN gold.dim_products p USING (product_sk)
LEFT JOIN gold.dim_stores s USING (store_sk)
LEFT JOIN gold.dim_employees e USING (employee_sk)
LEFT JOIN gold.dim_date d USING (date_key)
WHERE c.customer_sk IS NULL OR p.product_sk IS NULL OR s.store_sk IS NULL
   OR (f.employee_sk IS NOT NULL AND e.employee_sk IS NULL)
   OR (f.date_key IS NOT NULL AND d.date_key IS NULL);

SELECT order_item_id FROM gold.fact_sales
WHERE quantity <= 0 OR discount_pct IS NULL OR discount_pct NOT BETWEEN 0 AND 1
   OR gross_amount IS DISTINCT FROM ROUND(quantity * unit_price, 2)
   OR discount_amount IS DISTINCT FROM ROUND(quantity * unit_price * discount_pct, 2)
   OR net_amount IS DISTINCT FROM ROUND(quantity * unit_price * (1-discount_pct), 2)
   OR total_cost IS DISTINCT FROM ROUND(quantity * unit_cost, 2)
   OR margin_profit IS DISTINCT FROM ROUND(quantity * unit_price * (1-discount_pct) - quantity * unit_cost, 2);

SELECT customer_id, phone FROM silver.customers
WHERE phone IS NOT NULL AND phone !~ '^[0-9]+$';
SELECT customer_id, email FROM silver.customers
WHERE email IS NOT NULL AND email NOT LIKE '%@%.%';
SELECT employee_id, email FROM silver.employees
WHERE email IS NOT NULL AND email NOT LIKE '%@%.%';

-- Informational: review missing values and zero defaults before reporting.
SELECT COUNT(*) AS fact_rows,
       COUNT(*) FILTER (WHERE date_key IS NULL) AS missing_dates,
       COUNT(*) FILTER (WHERE employee_sk IS NULL) AS missing_employees,
       COUNT(*) FILTER (WHERE unit_price = 0) AS zero_prices,
       COUNT(*) FILTER (WHERE unit_cost = 0) AS zero_costs
FROM gold.fact_sales;

SELECT COUNT(*) FILTER (WHERE i.unit_price IS NULL) AS item_price_missing,
       COUNT(*) FILTER (WHERE i.unit_price IS NULL AND p.unit_price IS NULL) AS price_defaults_to_zero,
       COUNT(*) FILTER (WHERE p.unit_cost IS NULL) AS cost_defaults_to_zero
FROM silver.order_items i JOIN silver.products p USING (product_id);

-- True SQL NULL discounts can become 1 in the original Silver LEAST expression.
SELECT COUNT(*) AS bronze_sql_null_discounts FROM bronze.orders WHERE discount_pct IS NULL;
SELECT order_status, COUNT(*) AS lines, SUM(net_amount) AS net_amount
FROM gold.fact_sales GROUP BY order_status ORDER BY order_status;
