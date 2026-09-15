# Source data

Provide these six CSV files locally in this folder. Source data was not included in this repository. All data files are ignored by Git by default. Use shareable, appropriately anonymized data if you later choose to publish samples.

Each file needs a header row and the following column order. Headers are skipped rather than mapped by name. Bronze stores all fields as text.

- **customers.csv:** `customer_id, first_name, last_name, email, phone, city, country, signup_date, membership_type, birth_date`
- **employees.csv:** `employee_id, full_name, store_id, role, hire_date, salary, email`
- **products.csv:** `product_id, product_name, category, subcategory, unit_price, unit_cost, supplier, active`
- **stores.csv:** `store_id, store_name, city, country, region, open_date, store_size_sqm`
- **orders.csv:** `order_id, customer_id, store_id, employee_id, order_date, payment_method, discount_pct, order_status`
- **order_items.csv:** `order_item_id, order_id, product_id, quantity, unit_price`


From the repository root, run `sql/load_bronze.psql` with psql as described in the main README. The helper replaces Bronze atomically when invoked with `--single-transaction`. It does not refresh Silver or Gold.
