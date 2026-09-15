-- =============================================================================
-- RETAIL DATA WAREHOUSE — FINAL SIMPLIFIED PORTFOLIO VERSION
-- Engine: PostgreSQL
-- Architecture: Bronze -> Silver -> Gold
--
-- IMPORTANT
--   1) Run this setup script ONCE.
--   2) Load Bronze data separately when your source files change.
--   3) For normal warehouse refreshes, run only:
--
--          CALL public.refresh_warehouse();
--
--   Do NOT rerun the COPY statements every time or Bronze will duplicate data.
-- =============================================================================


-- =============================================================================
-- SECTION 0 — SCHEMAS
-- =============================================================================

CREATE SCHEMA IF NOT EXISTS bronze;

DROP SCHEMA IF EXISTS gold CASCADE;
DROP SCHEMA IF EXISTS silver CASCADE;

CREATE SCHEMA silver;
CREATE SCHEMA gold;


-- =============================================================================
-- SECTION 1 — BRONZE TABLES
-- =============================================================================
-- Bronze keeps the raw source values as TEXT.

CREATE TABLE IF NOT EXISTS bronze.customers (
    customer_id      TEXT,
    first_name       TEXT,
    last_name        TEXT,
    email            TEXT,
    phone            TEXT,
    city             TEXT,
    country          TEXT,
    signup_date      TEXT,
    membership_type  TEXT,
    birth_date       TEXT
);

CREATE TABLE IF NOT EXISTS bronze.employees (
    employee_id  TEXT,
    full_name    TEXT,
    store_id     TEXT,
    "role"       TEXT,
    hire_date    TEXT,
    salary       TEXT,
    email        TEXT
);

CREATE TABLE IF NOT EXISTS bronze.products (
    product_id    TEXT,
    product_name  TEXT,
    category      TEXT,
    subcategory   TEXT,
    unit_price    TEXT,
    unit_cost     TEXT,
    supplier      TEXT,
    active        TEXT
);

CREATE TABLE IF NOT EXISTS bronze.stores (
    store_id        TEXT,
    store_name      TEXT,
    city            TEXT,
    country         TEXT,
    region          TEXT,
    open_date       TEXT,
    store_size_sqm  TEXT
);

CREATE TABLE IF NOT EXISTS bronze.orders (
    order_id        TEXT,
    customer_id     TEXT,
    store_id        TEXT,
    employee_id     TEXT,
    order_date      TEXT,
    payment_method  TEXT,
    discount_pct    TEXT,
    order_status    TEXT
);

CREATE TABLE IF NOT EXISTS bronze.order_items (
    order_item_id  TEXT,
    order_id       TEXT,
    product_id     TEXT,
    quantity       TEXT,
    unit_price     TEXT
);


-- =============================================================================
-- SECTION 2 — BRONZE RELOAD (RUN ONLY WHEN SOURCE FILES CHANGE)
-- =============================================================================
-- Uncomment this section ONLY when you intentionally want to replace Bronze.
-- The TRUNCATE prevents the same CSVs from being appended repeatedly.
--
-- TRUNCATE TABLE
--     bronze.order_items,
--     bronze.orders,
--     bronze.employees,
--     bronze.products,
--     bronze.stores,
--     bronze.customers;
--
-- COPY bronze.customers
-- FROM 'C:/files/customers.csv'
-- WITH (FORMAT CSV, HEADER TRUE);
--
-- COPY bronze.employees
-- FROM 'C:/files/employees.csv'
-- WITH (FORMAT CSV, HEADER TRUE);
--
-- COPY bronze.products
-- FROM 'C:/files/products.csv'
-- WITH (FORMAT CSV, HEADER TRUE);
--
-- COPY bronze.stores
-- FROM 'C:/files/stores.csv'
-- WITH (FORMAT CSV, HEADER TRUE);
--
-- COPY bronze.orders
-- FROM 'C:/files/orders.csv'
-- WITH (FORMAT CSV, HEADER TRUE);
--
-- COPY bronze.order_items
-- FROM 'C:/files/order_items.csv'
-- WITH (FORMAT CSV, HEADER TRUE);


-- =============================================================================
-- SECTION 3 — SILVER TABLES
-- =============================================================================

CREATE TABLE silver.customers (
    customer_id       INT PRIMARY KEY,
    first_name        VARCHAR(100) NOT NULL,
    last_name         VARCHAR(100),
    email             VARCHAR(255),
    phone             VARCHAR(50),
    city              VARCHAR(100),
    country           VARCHAR(100),
    signup_date       DATE,
    membership_type   VARCHAR(50),
    birth_date        DATE,
    silver_loaded_at  TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE silver.stores (
    store_id          INT PRIMARY KEY,
    store_name        VARCHAR(150) NOT NULL,
    city              VARCHAR(100),
    country           VARCHAR(100),
    region            VARCHAR(100),
    open_date         DATE,
    store_size_sqm    NUMERIC(10,2),
    silver_loaded_at  TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE silver.employees (
    employee_id       INT PRIMARY KEY,
    full_name         VARCHAR(200) NOT NULL,
    store_id          INT,
    role              VARCHAR(100),
    hire_date         DATE,
    salary            NUMERIC(12,2),
    email             VARCHAR(255),
    silver_loaded_at  TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE silver.products (
    product_id        INT PRIMARY KEY,
    product_name      VARCHAR(200) NOT NULL,
    category          VARCHAR(100),
    subcategory       VARCHAR(100),
    unit_price        NUMERIC(10,2),
    unit_cost         NUMERIC(10,2),
    supplier          VARCHAR(150),
    is_active         BOOLEAN,
    silver_loaded_at  TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE silver.orders (
    order_id          INT PRIMARY KEY,
    customer_id       INT REFERENCES silver.customers(customer_id),
    store_id          INT REFERENCES silver.stores(store_id),
    employee_id       INT REFERENCES silver.employees(employee_id),
    order_date        DATE,
    payment_method    VARCHAR(50),
    discount_pct      NUMERIC(5,4) DEFAULT 0.0000
                      CHECK (discount_pct BETWEEN 0 AND 1),
    order_status      VARCHAR(50),
    silver_loaded_at  TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE silver.order_items (
    order_item_id     INT PRIMARY KEY,
    order_id          INT REFERENCES silver.orders(order_id) ON DELETE CASCADE,
    product_id        INT REFERENCES silver.products(product_id),
    quantity          INT CHECK (quantity > 0),
    unit_price        NUMERIC(10,2),
    silver_loaded_at  TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);


-- =============================================================================
-- SECTION 4 — PROCEDURE 1: BRONZE -> SILVER FULL CLEANING
-- =============================================================================

CREATE OR REPLACE PROCEDURE silver.load_silver()
LANGUAGE plpgsql
AS $$
BEGIN

    -- -------------------------------------------------------------------------
    -- CUSTOMERS
    -- -------------------------------------------------------------------------

    WITH customers_clean AS (
        SELECT
            customer_id::INT AS customer_id,
            INITCAP(TRIM(first_name)) AS first_name,

            CASE
                WHEN LOWER(TRIM(last_name))
                     IN ('', '-', 'n/a', 'nan', 'null', '<null>', 'none')
                    THEN NULL
                ELSE INITCAP(TRIM(last_name))
            END AS last_name,

            CASE
                WHEN LOWER(TRIM(email))
                     IN ('', '-', 'n/a', 'nan', 'null', '<null>', 'none', 'invalid_email')
                    THEN NULL
                WHEN LOWER(TRIM(email)) LIKE '%atgmail.com'
                    THEN REPLACE(LOWER(TRIM(email)), 'atgmail.com', '@gmail.com')
                WHEN LOWER(TRIM(email)) LIKE '%athotmail.com'
                    THEN REPLACE(LOWER(TRIM(email)), 'athotmail.com', '@hotmail.com')
                WHEN LOWER(TRIM(email)) LIKE '%atoutlook.com'
                    THEN REPLACE(LOWER(TRIM(email)), 'atoutlook.com', '@outlook.com')
                WHEN LOWER(TRIM(email)) LIKE '%atyahoo.com'
                    THEN REPLACE(LOWER(TRIM(email)), 'atyahoo.com', '@yahoo.com')
                WHEN LOWER(TRIM(email)) NOT LIKE '%@%'
                     AND LOWER(TRIM(email)) LIKE '%gmail.com'
                    THEN REPLACE(LOWER(TRIM(email)), 'gmail.com', '@gmail.com')
                WHEN LOWER(TRIM(email)) NOT LIKE '%@%'
                     AND LOWER(TRIM(email)) LIKE '%hotmail.com'
                    THEN REPLACE(LOWER(TRIM(email)), 'hotmail.com', '@hotmail.com')
                WHEN LOWER(TRIM(email)) NOT LIKE '%@%'
                     AND LOWER(TRIM(email)) LIKE '%outlook.com'
                    THEN REPLACE(LOWER(TRIM(email)), 'outlook.com', '@outlook.com')
                WHEN LOWER(TRIM(email)) NOT LIKE '%@%'
                     AND LOWER(TRIM(email)) LIKE '%yahoo.com'
                    THEN REPLACE(LOWER(TRIM(email)), 'yahoo.com', '@yahoo.com')
                ELSE LOWER(TRIM(email))
            END AS clean_email,

            CASE
                WHEN LOWER(TRIM(phone))
                     IN ('', '-', 'n/a', 'nan', 'null', '<null>', 'none')
                    THEN NULL
                ELSE REGEXP_REPLACE(TRIM(phone), '[^0-9]', '', 'g')
            END AS phone,

            CASE
                WHEN LOWER(TRIM(city))
                     IN ('', '-', 'n/a', 'nan', 'null', '<null>', 'none')
                    THEN NULL
                ELSE INITCAP(TRIM(city))
            END AS city,

            CASE
                WHEN UPPER(TRIM(country)) = 'EGYPT' THEN 'Egypt'
                WHEN UPPER(TRIM(country)) IN ('HASHEMITE KINGDOM OF JORDAN', 'JO', 'JORDAN')
                    THEN 'Jordan'
                WHEN UPPER(TRIM(country)) IN ('KINGDOM OF SAUDI ARABIA', 'KSA', 'SAUDI ARABIA')
                    THEN 'Saudi Arabia'
                WHEN UPPER(TRIM(country)) IN ('UAE', 'U.A.E.', 'UNITED ARAB EMIRATES')
                    THEN 'United Arab Emirates'
                WHEN UPPER(TRIM(country)) IN ('UK', 'U.K.', 'UNITED KINGDOM')
                    THEN 'United Kingdom'
                WHEN UPPER(TRIM(country)) IN ('US', 'USA', 'U.S.A.', 'UNITED STATES')
                    THEN 'United States'
                WHEN LOWER(TRIM(country)) IN ('', '-', 'n/a', 'nan', 'null', '<null>', 'none')
                    THEN NULL
                ELSE INITCAP(TRIM(country))
            END AS country,

            CASE
                WHEN NULLIF(TRIM(signup_date), '') IS NULL
                     OR LOWER(TRIM(signup_date)) IN ('null', 'none', 'n/a', '-', 'nan', '<null>')
                    THEN NULL
                WHEN TRIM(signup_date) ~ '^\d{4}[-/]\d{1,2}[-/]\d{1,2}$'
                    THEN TO_DATE(REPLACE(TRIM(signup_date), '/', '-'), 'YYYY-MM-DD')
                WHEN TRIM(signup_date) ~ '^\d{1,2}/\d{1,2}/\d{4}$'
                    THEN CASE
                        WHEN SPLIT_PART(TRIM(signup_date), '/', 1)::INT > 12
                            THEN TO_DATE(TRIM(signup_date), 'DD/MM/YYYY')
                        WHEN SPLIT_PART(TRIM(signup_date), '/', 2)::INT > 12
                            THEN TO_DATE(TRIM(signup_date), 'MM/DD/YYYY')
                        ELSE TO_DATE(TRIM(signup_date), 'MM/DD/YYYY')
                    END
                WHEN TRIM(signup_date) ~ '^\d{1,2}-\d{1,2}-\d{4}$'
                    THEN CASE
                        WHEN SPLIT_PART(TRIM(signup_date), '-', 1)::INT > 12
                            THEN TO_DATE(TRIM(signup_date), 'DD-MM-YYYY')
                        WHEN SPLIT_PART(TRIM(signup_date), '-', 2)::INT > 12
                            THEN TO_DATE(TRIM(signup_date), 'MM-DD-YYYY')
                        ELSE TO_DATE(TRIM(signup_date), 'MM-DD-YYYY')
                    END
                WHEN TRIM(signup_date) ~* '^[A-Za-z]+[[:space:]]+[0-9]{1,2},[[:space:]]+[0-9]{4}$'
                    THEN TO_DATE(TRIM(signup_date), 'Month DD, YYYY')
                WHEN TRIM(signup_date) ~* '^[0-9]{1,2}[[:space:]]+[A-Za-z]+[[:space:]]+[0-9]{4}$'
                    THEN TO_DATE(TRIM(signup_date), 'DD Mon YYYY')
                ELSE NULL
            END AS signup_date,

            CASE
                WHEN LOWER(TRIM(membership_type))
                     IN ('', '-', 'n/a', 'nan', 'null', '<null>', 'none')
                    THEN NULL
                ELSE INITCAP(TRIM(membership_type))
            END AS membership_type,

            CASE
                WHEN NULLIF(TRIM(birth_date), '') IS NULL
                     OR LOWER(TRIM(birth_date)) IN ('null', 'none', 'n/a', '-', 'nan', '<null>')
                    THEN NULL
                WHEN TRIM(birth_date) ~ '^\d{4}[-/]\d{1,2}[-/]\d{1,2}$'
                    THEN TO_DATE(REPLACE(TRIM(birth_date), '/', '-'), 'YYYY-MM-DD')
                WHEN TRIM(birth_date) ~ '^\d{1,2}/\d{1,2}/\d{4}$'
                    THEN CASE
                        WHEN SPLIT_PART(TRIM(birth_date), '/', 1)::INT > 12
                            THEN TO_DATE(TRIM(birth_date), 'DD/MM/YYYY')
                        WHEN SPLIT_PART(TRIM(birth_date), '/', 2)::INT > 12
                            THEN TO_DATE(TRIM(birth_date), 'MM/DD/YYYY')
                        ELSE TO_DATE(TRIM(birth_date), 'MM/DD/YYYY')
                    END
                WHEN TRIM(birth_date) ~ '^\d{1,2}-\d{1,2}-\d{4}$'
                    THEN CASE
                        WHEN SPLIT_PART(TRIM(birth_date), '-', 1)::INT > 12
                            THEN TO_DATE(TRIM(birth_date), 'DD-MM-YYYY')
                        WHEN SPLIT_PART(TRIM(birth_date), '-', 2)::INT > 12
                            THEN TO_DATE(TRIM(birth_date), 'MM-DD-YYYY')
                        ELSE TO_DATE(TRIM(birth_date), 'MM-DD-YYYY')
                    END
                WHEN TRIM(birth_date) ~* '^[A-Za-z]+[[:space:]]+[0-9]{1,2},[[:space:]]+[0-9]{4}$'
                    THEN TO_DATE(TRIM(birth_date), 'Month DD, YYYY')
                WHEN TRIM(birth_date) ~* '^[0-9]{1,2}[[:space:]]+[A-Za-z]+[[:space:]]+[0-9]{4}$'
                    THEN TO_DATE(TRIM(birth_date), 'DD Mon YYYY')
                ELSE NULL
            END AS birth_date

        FROM bronze.customers
        WHERE NULLIF(TRIM(customer_id), '') IS NOT NULL
    ),
    deduplicated_customers AS (
        SELECT
            *,
            ROW_NUMBER() OVER (
                PARTITION BY customer_id
                ORDER BY
                    (
                        (clean_email IS NOT NULL)::INT
                      + (phone IS NOT NULL)::INT
                      + (signup_date IS NOT NULL)::INT
                      + (birth_date IS NOT NULL)::INT
                    ) DESC,
                    signup_date DESC NULLS LAST
            ) AS rn
        FROM customers_clean
    )
    INSERT INTO silver.customers (
        customer_id, first_name, last_name, email, phone,
        city, country, signup_date, membership_type, birth_date
    )
    SELECT
        customer_id,
        first_name,
        last_name,
        CASE WHEN clean_email LIKE '%@%.%' THEN clean_email ELSE NULL END,
        phone,
        city,
        country,
        signup_date,
        membership_type,
        birth_date
    FROM deduplicated_customers
    WHERE rn = 1;


    -- -------------------------------------------------------------------------
    -- STORES
    -- -------------------------------------------------------------------------

    WITH clean_stores AS (
        SELECT
            store_id::INT AS store_id,
            INITCAP(TRIM(store_name)) AS store_name,

            CASE
                WHEN LOWER(TRIM(city)) IN ('', '-', 'n/a', 'nan', 'null', '<null>', 'none')
                    THEN NULL
                ELSE INITCAP(TRIM(city))
            END AS city,

            CASE
                WHEN UPPER(TRIM(country)) = 'EGYPT' THEN 'Egypt'
                WHEN UPPER(TRIM(country)) IN ('HASHEMITE KINGDOM OF JORDAN', 'JO', 'JORDAN')
                    THEN 'Jordan'
                WHEN UPPER(TRIM(country)) IN ('KINGDOM OF SAUDI ARABIA', 'KSA', 'SAUDI ARABIA')
                    THEN 'Saudi Arabia'
                WHEN UPPER(TRIM(country)) IN ('UAE', 'U.A.E.', 'UNITED ARAB EMIRATES')
                    THEN 'United Arab Emirates'
                WHEN UPPER(TRIM(country)) IN ('UK', 'U.K.', 'UNITED KINGDOM')
                    THEN 'United Kingdom'
                WHEN UPPER(TRIM(country)) IN ('US', 'USA', 'U.S.A.', 'UNITED STATES')
                    THEN 'United States'
                WHEN LOWER(TRIM(country)) IN ('', '-', 'n/a', 'nan', 'null', '<null>', 'none')
                    THEN NULL
                ELSE INITCAP(TRIM(country))
            END AS country,

            CASE
                WHEN UPPER(TRIM(region)) IN ('MENA', 'MIDDLE EAST', 'MIDDLE EAST & NORTH AFRICA')
                    THEN 'MENA'
                WHEN LOWER(TRIM(region)) IN ('', '-', 'n/a', 'nan', 'null', '<null>', 'none')
                    THEN NULL
                ELSE INITCAP(TRIM(region))
            END AS region,

            CASE
                WHEN NULLIF(TRIM(open_date), '') IS NULL
                     OR LOWER(TRIM(open_date)) IN ('null', 'none', 'n/a', '-', 'nan', '<null>')
                    THEN NULL
                WHEN TRIM(open_date) ~ '^\d{4}[-/]\d{1,2}[-/]\d{1,2}$'
                    THEN TO_DATE(REPLACE(TRIM(open_date), '/', '-'), 'YYYY-MM-DD')
                WHEN TRIM(open_date) ~ '^\d{1,2}/\d{1,2}/\d{4}$'
                    THEN CASE
                        WHEN SPLIT_PART(TRIM(open_date), '/', 1)::INT > 12
                            THEN TO_DATE(TRIM(open_date), 'DD/MM/YYYY')
                        WHEN SPLIT_PART(TRIM(open_date), '/', 2)::INT > 12
                            THEN TO_DATE(TRIM(open_date), 'MM/DD/YYYY')
                        ELSE TO_DATE(TRIM(open_date), 'MM/DD/YYYY')
                    END
                WHEN TRIM(open_date) ~ '^\d{1,2}-\d{1,2}-\d{4}$'
                    THEN CASE
                        WHEN SPLIT_PART(TRIM(open_date), '-', 1)::INT > 12
                            THEN TO_DATE(TRIM(open_date), 'DD-MM-YYYY')
                        WHEN SPLIT_PART(TRIM(open_date), '-', 2)::INT > 12
                            THEN TO_DATE(TRIM(open_date), 'MM-DD-YYYY')
                        ELSE TO_DATE(TRIM(open_date), 'MM-DD-YYYY')
                    END
                WHEN TRIM(open_date) ~* '^[A-Za-z]+[[:space:]]+[0-9]{1,2},[[:space:]]+[0-9]{4}$'
                    THEN TO_DATE(TRIM(open_date), 'Month DD, YYYY')
                WHEN TRIM(open_date) ~* '^[0-9]{1,2}[[:space:]]+[A-Za-z]+[[:space:]]+[0-9]{4}$'
                    THEN TO_DATE(TRIM(open_date), 'DD Mon YYYY')
                ELSE NULL
            END AS open_date,

            CASE
                WHEN LOWER(TRIM(store_size_sqm)) IN ('', '-', 'n/a', 'nan', 'null', '<null>', 'none')
                    THEN NULL
                ELSE ABS(
                    REGEXP_REPLACE(TRIM(store_size_sqm), '[^0-9.\-]', '', 'g')::NUMERIC(10,2)
                )
            END AS store_size_sqm

        FROM bronze.stores
        WHERE NULLIF(TRIM(store_id), '') IS NOT NULL
    ),
    deduplicated_stores AS (
        SELECT
            *,
            ROW_NUMBER() OVER (
                PARTITION BY store_id
                ORDER BY open_date DESC NULLS LAST
            ) AS rn
        FROM clean_stores
    )
    INSERT INTO silver.stores (
        store_id, store_name, city, country, region, open_date, store_size_sqm
    )
    SELECT
        store_id, store_name, city, country, region, open_date, store_size_sqm
    FROM deduplicated_stores
    WHERE rn = 1;


    -- -------------------------------------------------------------------------
    -- EMPLOYEES
    -- -------------------------------------------------------------------------

    WITH clean_employees AS (
        SELECT
            employee_id::INT AS employee_id,
            INITCAP(TRIM(full_name)) AS full_name,
            NULLIF(TRIM(store_id), '')::INT AS store_id,

            CASE
                WHEN LOWER(TRIM("role")) IN ('', '-', 'n/a', 'nan', 'null', '<null>', 'none')
                    THEN NULL
                ELSE INITCAP(TRIM("role"))
            END AS role,

            CASE
                WHEN NULLIF(TRIM(hire_date), '') IS NULL
                     OR LOWER(TRIM(hire_date)) IN ('null', 'none', 'n/a', '-', 'nan', '<null>')
                    THEN NULL
                WHEN TRIM(hire_date) ~ '^\d{4}[-/]\d{1,2}[-/]\d{1,2}$'
                    THEN TO_DATE(REPLACE(TRIM(hire_date), '/', '-'), 'YYYY-MM-DD')
                WHEN TRIM(hire_date) ~ '^\d{1,2}/\d{1,2}/\d{4}$'
                    THEN CASE
                        WHEN SPLIT_PART(TRIM(hire_date), '/', 1)::INT > 12
                            THEN TO_DATE(TRIM(hire_date), 'DD/MM/YYYY')
                        WHEN SPLIT_PART(TRIM(hire_date), '/', 2)::INT > 12
                            THEN TO_DATE(TRIM(hire_date), 'MM/DD/YYYY')
                        ELSE TO_DATE(TRIM(hire_date), 'MM/DD/YYYY')
                    END
                WHEN TRIM(hire_date) ~ '^\d{1,2}-\d{1,2}-\d{4}$'
                    THEN CASE
                        WHEN SPLIT_PART(TRIM(hire_date), '-', 1)::INT > 12
                            THEN TO_DATE(TRIM(hire_date), 'DD-MM-YYYY')
                        WHEN SPLIT_PART(TRIM(hire_date), '-', 2)::INT > 12
                            THEN TO_DATE(TRIM(hire_date), 'MM-DD-YYYY')
                        ELSE TO_DATE(TRIM(hire_date), 'MM-DD-YYYY')
                    END
                WHEN TRIM(hire_date) ~* '^[A-Za-z]+[[:space:]]+[0-9]{1,2},[[:space:]]+[0-9]{4}$'
                    THEN TO_DATE(TRIM(hire_date), 'Month DD, YYYY')
                WHEN TRIM(hire_date) ~* '^[0-9]{1,2}[[:space:]]+[A-Za-z]+[[:space:]]+[0-9]{4}$'
                    THEN TO_DATE(TRIM(hire_date), 'DD Mon YYYY')
                ELSE NULL
            END AS hire_date,

            CASE
                WHEN LOWER(TRIM(salary)) IN ('', '-', 'n/a', 'nan', 'null', '<null>', 'none')
                    THEN NULL
                ELSE ABS(
                    REGEXP_REPLACE(TRIM(salary), '[^0-9.\-]', '', 'g')::NUMERIC(12,2)
                )
            END AS salary,

            CASE
                WHEN LOWER(TRIM(email))
                     IN ('', '-', 'n/a', 'nan', 'null', '<null>', 'none', 'invalid_email')
                    THEN NULL
                WHEN LOWER(TRIM(email)) LIKE '%atgmail.com'
                    THEN REPLACE(LOWER(TRIM(email)), 'atgmail.com', '@gmail.com')
                WHEN LOWER(TRIM(email)) LIKE '%athotmail.com'
                    THEN REPLACE(LOWER(TRIM(email)), 'athotmail.com', '@hotmail.com')
                WHEN LOWER(TRIM(email)) LIKE '%atoutlook.com'
                    THEN REPLACE(LOWER(TRIM(email)), 'atoutlook.com', '@outlook.com')
                WHEN LOWER(TRIM(email)) LIKE '%atyahoo.com'
                    THEN REPLACE(LOWER(TRIM(email)), 'atyahoo.com', '@yahoo.com')
                WHEN LOWER(TRIM(email)) NOT LIKE '%@%'
                     AND LOWER(TRIM(email)) LIKE '%gmail.com'
                    THEN REPLACE(LOWER(TRIM(email)), 'gmail.com', '@gmail.com')
                WHEN LOWER(TRIM(email)) NOT LIKE '%@%'
                     AND LOWER(TRIM(email)) LIKE '%hotmail.com'
                    THEN REPLACE(LOWER(TRIM(email)), 'hotmail.com', '@hotmail.com')
                WHEN LOWER(TRIM(email)) NOT LIKE '%@%'
                     AND LOWER(TRIM(email)) LIKE '%outlook.com'
                    THEN REPLACE(LOWER(TRIM(email)), 'outlook.com', '@outlook.com')
                WHEN LOWER(TRIM(email)) NOT LIKE '%@%'
                     AND LOWER(TRIM(email)) LIKE '%yahoo.com'
                    THEN REPLACE(LOWER(TRIM(email)), 'yahoo.com', '@yahoo.com')
                ELSE LOWER(TRIM(email))
            END AS clean_email

        FROM bronze.employees
        WHERE NULLIF(TRIM(employee_id), '') IS NOT NULL
    ),
    deduplicated_employees AS (
        SELECT
            *,
            ROW_NUMBER() OVER (
                PARTITION BY employee_id
                ORDER BY
                    (
                        (hire_date IS NOT NULL)::INT
                      + (salary IS NOT NULL)::INT
                      + (clean_email IS NOT NULL)::INT
                    ) DESC,
                    hire_date DESC NULLS LAST
            ) AS rn
        FROM clean_employees
    )
    INSERT INTO silver.employees (
        employee_id, full_name, store_id, role, hire_date, salary, email
    )
    SELECT
        employee_id,
        full_name,
        store_id,
        role,
        hire_date,
        salary,
        CASE WHEN clean_email LIKE '%@%.%' THEN clean_email ELSE NULL END
    FROM deduplicated_employees
    WHERE rn = 1;


    -- -------------------------------------------------------------------------
    -- PRODUCTS
    -- -------------------------------------------------------------------------

    WITH clean_products AS (
        SELECT
            product_id::INT AS product_id,

            CASE
                WHEN TRIM(product_name) LIKE 'I %'
                    THEN TRIM(SUBSTRING(TRIM(product_name) FROM 3))
                ELSE TRIM(product_name)
            END AS product_name,

            CASE
                WHEN UPPER(TRIM(category)) = 'BEAUTY' THEN 'Beauty'
                WHEN UPPER(TRIM(category)) IN ('CLOTHES', 'CLOTHING') THEN 'Clothing'
                WHEN UPPER(TRIM(category)) IN ('ELECTRONIC', 'ELECTRONICS') THEN 'Electronics'
                WHEN UPPER(TRIM(category)) IN ('GROCERIES', 'GROCERY') THEN 'Grocery'
                WHEN UPPER(TRIM(category)) IN ('HOME & KITCHEN', 'HOME AND KITCHEN')
                    THEN 'Home & Kitchen'
                WHEN UPPER(TRIM(category)) = 'TOYS' THEN 'Toys'
                WHEN LOWER(TRIM(category)) IN ('', '-', 'n/a', 'nan', 'null', '<null>', 'none')
                    THEN NULL
                ELSE INITCAP(TRIM(category))
            END AS category,

            CASE
                WHEN LOWER(TRIM(subcategory)) IN ('', '-', 'n/a', 'nan', 'null', '<null>', 'none')
                    THEN NULL
                ELSE INITCAP(TRIM(subcategory))
            END AS subcategory,

            CASE
                WHEN LOWER(TRIM(unit_price)) IN ('', '-', 'n/a', 'nan', 'null', '<null>', 'none')
                    THEN NULL
                ELSE ABS(
                    REGEXP_REPLACE(
                        REPLACE(UPPER(TRIM(unit_price)), 'JOD', ''),
                        '[^0-9.\-]',
                        '',
                        'g'
                    )::NUMERIC(10,2)
                )
            END AS unit_price,

            CASE
                WHEN LOWER(TRIM(unit_cost)) IN ('', '-', 'n/a', 'nan', 'null', '<null>', 'none')
                    THEN NULL
                ELSE ABS(
                    REGEXP_REPLACE(
                        REPLACE(UPPER(TRIM(unit_cost)), 'JOD', ''),
                        '[^0-9.\-]',
                        '',
                        'g'
                    )::NUMERIC(10,2)
                )
            END AS unit_cost,

            CASE
                WHEN LOWER(TRIM(supplier)) IN ('', '-', 'n/a', 'nan', 'null', '<null>', 'none')
                    THEN NULL
                ELSE INITCAP(TRIM(supplier))
            END AS supplier,

            CASE
                WHEN LOWER(TRIM(active)) IN ('1', 'true', 'yes', 'y', 'active') THEN TRUE
                WHEN LOWER(TRIM(active)) IN ('0', 'false', 'no', 'n', 'inactive') THEN FALSE
                ELSE NULL
            END AS is_active

        FROM bronze.products
        WHERE NULLIF(TRIM(product_id), '') IS NOT NULL
    ),
    deduplicated_products AS (
        SELECT
            *,
            ROW_NUMBER() OVER (
                PARTITION BY product_id
                ORDER BY
                    ((unit_price IS NOT NULL)::INT + (unit_cost IS NOT NULL)::INT) DESC
            ) AS rn
        FROM clean_products
    )
    INSERT INTO silver.products (
        product_id, product_name, category, subcategory,
        unit_price, unit_cost, supplier, is_active
    )
    SELECT
        product_id, product_name, category, subcategory,
        unit_price, unit_cost, supplier, is_active
    FROM deduplicated_products
    WHERE rn = 1;


    -- -------------------------------------------------------------------------
    -- ORDERS
    -- -------------------------------------------------------------------------

    WITH clean_orders AS (
        SELECT
            order_id::INT AS order_id,
            NULLIF(TRIM(customer_id), '')::INT AS customer_id,
            NULLIF(TRIM(store_id), '')::INT AS store_id,
            NULLIF(TRIM(employee_id), '')::INT AS employee_id,

            CASE
                WHEN NULLIF(TRIM(order_date), '') IS NULL
                     OR LOWER(TRIM(order_date)) IN ('null', 'none', 'n/a', '-', 'nan', '<null>')
                    THEN NULL
                WHEN TRIM(order_date) ~ '^\d{4}[-/]\d{1,2}[-/]\d{1,2}$'
                    THEN TO_DATE(REPLACE(TRIM(order_date), '/', '-'), 'YYYY-MM-DD')
                WHEN TRIM(order_date) ~ '^\d{1,2}/\d{1,2}/\d{4}$'
                    THEN CASE
                        WHEN SPLIT_PART(TRIM(order_date), '/', 1)::INT > 12
                            THEN TO_DATE(TRIM(order_date), 'DD/MM/YYYY')
                        WHEN SPLIT_PART(TRIM(order_date), '/', 2)::INT > 12
                            THEN TO_DATE(TRIM(order_date), 'MM/DD/YYYY')
                        ELSE TO_DATE(TRIM(order_date), 'MM/DD/YYYY')
                    END
                WHEN TRIM(order_date) ~ '^\d{1,2}-\d{1,2}-\d{4}$'
                    THEN CASE
                        WHEN SPLIT_PART(TRIM(order_date), '-', 1)::INT > 12
                            THEN TO_DATE(TRIM(order_date), 'DD-MM-YYYY')
                        WHEN SPLIT_PART(TRIM(order_date), '-', 2)::INT > 12
                            THEN TO_DATE(TRIM(order_date), 'MM-DD-YYYY')
                        ELSE TO_DATE(TRIM(order_date), 'MM-DD-YYYY')
                    END
                WHEN TRIM(order_date) ~* '^[A-Za-z]+[[:space:]]+[0-9]{1,2},[[:space:]]+[0-9]{4}$'
                    THEN TO_DATE(TRIM(order_date), 'Month DD, YYYY')
                WHEN TRIM(order_date) ~* '^[0-9]{1,2}[[:space:]]+[A-Za-z]+[[:space:]]+[0-9]{4}$'
                    THEN TO_DATE(TRIM(order_date), 'DD Mon YYYY')
                ELSE NULL
            END AS order_date,

            CASE
                WHEN LOWER(TRIM(payment_method)) IN ('', '-', 'n/a', 'nan', 'null', '<null>', 'none')
                    THEN NULL
                WHEN UPPER(REGEXP_REPLACE(TRIM(payment_method), '\s+', ' ', 'g')) = 'CASH'
                    THEN 'Cash'
                WHEN UPPER(REGEXP_REPLACE(TRIM(payment_method), '\s+', ' ', 'g')) = 'CREDIT CARD'
                    THEN 'Credit Card'
                WHEN UPPER(REGEXP_REPLACE(TRIM(payment_method), '\s+', ' ', 'g')) LIKE 'DEBIT%'
                    THEN 'Debit Card'
                WHEN UPPER(REGEXP_REPLACE(TRIM(payment_method), '\s+', ' ', 'g')) = 'GIFT CARD'
                    THEN 'Gift Card'
                WHEN UPPER(REGEXP_REPLACE(TRIM(payment_method), '\s+', ' ', 'g')) = 'PAYPAL'
                    THEN 'PayPal'
                WHEN UPPER(REGEXP_REPLACE(TRIM(payment_method), '\s+', ' ', 'g')) = 'STORE CREDIT'
                    THEN 'Store Credit'
                ELSE INITCAP(REGEXP_REPLACE(TRIM(payment_method), '\s+', ' ', 'g'))
            END AS payment_method,

            CASE
                WHEN LOWER(TRIM(discount_pct)) IN ('', '-', 'n/a', 'nan', 'null', '<null>', 'none')
                    THEN 0.0000
                WHEN POSITION('%' IN TRIM(discount_pct)) > 0
                    THEN LEAST(
                        ABS(REPLACE(TRIM(discount_pct), '%', '')::NUMERIC) / 100.0,
                        1.0
                    )
                WHEN ABS(TRIM(discount_pct)::NUMERIC) > 1
                    THEN LEAST(ABS(TRIM(discount_pct)::NUMERIC) / 100.0, 1.0)
                ELSE LEAST(ABS(TRIM(discount_pct)::NUMERIC), 1.0)
            END::NUMERIC(5,4) AS discount_pct,

            CASE
                WHEN LOWER(TRIM(order_status)) IN ('', '-', 'n/a', 'nan', 'null', '<null>', 'none')
                    THEN NULL
                ELSE INITCAP(TRIM(order_status))
            END AS order_status

        FROM bronze.orders
        WHERE NULLIF(TRIM(order_id), '') IS NOT NULL
    ),
    deduplicated_orders AS (
        SELECT
            *,
            ROW_NUMBER() OVER (
                PARTITION BY order_id
                ORDER BY order_date DESC NULLS LAST
            ) AS rn
        FROM clean_orders
    )
    INSERT INTO silver.orders (
        order_id, customer_id, store_id, employee_id,
        order_date, payment_method, discount_pct, order_status
    )
    SELECT
        o.order_id,
        o.customer_id,
        o.store_id,
        e.employee_id,
        o.order_date,
        o.payment_method,
        o.discount_pct,
        o.order_status
    FROM deduplicated_orders o
    INNER JOIN silver.customers c
        ON o.customer_id = c.customer_id
    INNER JOIN silver.stores s
        ON o.store_id = s.store_id
    LEFT JOIN silver.employees e
        ON o.employee_id = e.employee_id
    WHERE o.rn = 1;


    -- -------------------------------------------------------------------------
    -- ORDER ITEMS
    -- -------------------------------------------------------------------------

    WITH clean_items AS (
        SELECT
            order_item_id::INT AS order_item_id,
            order_id::INT AS order_id,
            product_id::INT AS product_id,

            CASE
                WHEN LOWER(TRIM(quantity)) IN ('', '-', 'n/a', 'nan', 'null', '<null>', 'none')
                    THEN NULL
                ELSE ABS(TRIM(quantity)::INT)
            END AS quantity,

            CASE
                WHEN LOWER(TRIM(unit_price)) IN ('', '-', 'n/a', 'nan', 'null', '<null>', 'none')
                    THEN NULL
                ELSE ABS(
                    REGEXP_REPLACE(
                        REPLACE(UPPER(TRIM(unit_price)), 'JOD', ''),
                        '[^0-9.\-]',
                        '',
                        'g'
                    )::NUMERIC(10,2)
                )
            END AS unit_price

        FROM bronze.order_items
        WHERE NULLIF(TRIM(order_item_id), '') IS NOT NULL
    ),
    deduplicated_items AS (
        SELECT
            *,
            ROW_NUMBER() OVER (
                PARTITION BY order_item_id
                ORDER BY order_id
            ) AS rn
        FROM clean_items
    )
    INSERT INTO silver.order_items (
        order_item_id, order_id, product_id, quantity, unit_price
    )
    SELECT
        i.order_item_id,
        i.order_id,
        i.product_id,
        i.quantity,
        i.unit_price
    FROM deduplicated_items i
    INNER JOIN silver.orders o
        ON i.order_id = o.order_id
    INNER JOIN silver.products p
        ON i.product_id = p.product_id
    WHERE i.rn = 1
      AND i.quantity > 0;

END;
$$;


-- =============================================================================
-- SECTION 5 — SILVER INDEXES
-- =============================================================================

CREATE INDEX idx_silver_orders_customer_id
    ON silver.orders(customer_id);

CREATE INDEX idx_silver_orders_store_id
    ON silver.orders(store_id);

CREATE INDEX idx_silver_orders_employee_id
    ON silver.orders(employee_id);

CREATE INDEX idx_silver_orders_order_date
    ON silver.orders(order_date);

CREATE INDEX idx_silver_order_items_order_id
    ON silver.order_items(order_id);

CREATE INDEX idx_silver_order_items_product_id
    ON silver.order_items(product_id);


-- =============================================================================
-- SECTION 6 — GOLD TABLES
-- =============================================================================

CREATE TABLE gold.dim_date (
    date_key       INT PRIMARY KEY,
    full_date      DATE UNIQUE NOT NULL,
    year           INT NOT NULL,
    quarter        INT NOT NULL,
    quarter_name   VARCHAR(2) NOT NULL,
    month          INT NOT NULL,
    month_name     VARCHAR(20) NOT NULL,
    day_of_month   INT NOT NULL,
    day_of_week    INT NOT NULL,
    day_name       VARCHAR(20) NOT NULL,
    is_weekend     BOOLEAN NOT NULL
);

CREATE TABLE gold.dim_customers (
    customer_sk       INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    customer_id       INT UNIQUE NOT NULL,
    full_name         VARCHAR(200) NOT NULL,
    first_name        VARCHAR(100),
    last_name         VARCHAR(100),
    email             VARCHAR(255),
    phone             VARCHAR(50),
    city              VARCHAR(100),
    country           VARCHAR(100),
    signup_date       DATE,
    membership_type   VARCHAR(50),
    birth_date        DATE,
    gold_loaded_at    TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE gold.dim_products (
    product_sk       INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    product_id       INT UNIQUE NOT NULL,
    product_name     VARCHAR(200) NOT NULL,
    category         VARCHAR(100),
    subcategory      VARCHAR(100),
    unit_price       NUMERIC(10,2),
    unit_cost        NUMERIC(10,2),
    supplier         VARCHAR(150),
    is_active        BOOLEAN,
    gold_loaded_at   TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE gold.dim_stores (
    store_sk         INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    store_id         INT UNIQUE NOT NULL,
    store_name       VARCHAR(150) NOT NULL,
    city             VARCHAR(100),
    country          VARCHAR(100),
    region           VARCHAR(100),
    open_date        DATE,
    store_size_sqm   NUMERIC(10,2),
    gold_loaded_at   TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE gold.dim_employees (
    employee_sk      INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    employee_id      INT UNIQUE NOT NULL,
    full_name        VARCHAR(200) NOT NULL,
    role             VARCHAR(100),
    hire_date        DATE,
    salary           NUMERIC(12,2),
    email            VARCHAR(255),
    gold_loaded_at   TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Grain: one row per order-item line.
CREATE TABLE gold.fact_sales (
    sales_fact_id    BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    order_item_id    INT UNIQUE NOT NULL,
    order_id         INT NOT NULL,

    customer_sk      INT REFERENCES gold.dim_customers(customer_sk),
    product_sk       INT REFERENCES gold.dim_products(product_sk),
    store_sk         INT REFERENCES gold.dim_stores(store_sk),
    employee_sk      INT REFERENCES gold.dim_employees(employee_sk),
    date_key         INT REFERENCES gold.dim_date(date_key),

    payment_method   VARCHAR(50),
    order_status     VARCHAR(50),

    quantity         INT NOT NULL,
    unit_price       NUMERIC(10,2) NOT NULL,
    unit_cost        NUMERIC(10,2),
    discount_pct     NUMERIC(5,4),

    gross_amount     NUMERIC(12,2) NOT NULL,
    discount_amount  NUMERIC(12,2) NOT NULL,
    net_amount       NUMERIC(12,2) NOT NULL,
    total_cost       NUMERIC(12,2),
    margin_profit    NUMERIC(12,2),

    gold_loaded_at   TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);


-- =============================================================================
-- SECTION 7 — PROCEDURE 2: SILVER -> GOLD
-- =============================================================================

CREATE OR REPLACE PROCEDURE gold.load_gold()
LANGUAGE plpgsql
AS $$
DECLARE
    v_start_date DATE;
    v_end_date   DATE;
BEGIN

    SELECT
        COALESCE(DATE_TRUNC('year', MIN(order_date))::DATE, DATE '2020-01-01'),
        COALESCE(
            (DATE_TRUNC('year', MAX(order_date)) + INTERVAL '1 year - 1 day')::DATE,
            DATE '2030-12-31'
        )
    INTO v_start_date, v_end_date
    FROM silver.orders
    WHERE order_date IS NOT NULL;

    INSERT INTO gold.dim_date
    SELECT
        TO_CHAR(datum, 'YYYYMMDD')::INT,
        datum::DATE,
        EXTRACT(YEAR FROM datum)::INT,
        EXTRACT(QUARTER FROM datum)::INT,
        'Q' || EXTRACT(QUARTER FROM datum)::TEXT,
        EXTRACT(MONTH FROM datum)::INT,
        TRIM(TO_CHAR(datum, 'Month')),
        EXTRACT(DAY FROM datum)::INT,
        EXTRACT(ISODOW FROM datum)::INT,
        TRIM(TO_CHAR(datum, 'Day')),
        EXTRACT(ISODOW FROM datum) IN (6, 7)
    FROM generate_series(
        v_start_date::TIMESTAMP,
        v_end_date::TIMESTAMP,
        '1 day'::INTERVAL
    ) AS datum;


    INSERT INTO gold.dim_customers (
        customer_id, full_name, first_name, last_name, email, phone,
        city, country, signup_date, membership_type, birth_date
    )
    SELECT
        customer_id,
        TRIM(CONCAT_WS(' ', first_name, last_name)),
        first_name,
        last_name,
        email,
        phone,
        city,
        country,
        signup_date,
        membership_type,
        birth_date
    FROM silver.customers;


    INSERT INTO gold.dim_products (
        product_id, product_name, category, subcategory,
        unit_price, unit_cost, supplier, is_active
    )
    SELECT
        product_id, product_name, category, subcategory,
        unit_price, unit_cost, supplier, is_active
    FROM silver.products;


    INSERT INTO gold.dim_stores (
        store_id, store_name, city, country, region, open_date, store_size_sqm
    )
    SELECT
        store_id, store_name, city, country, region, open_date, store_size_sqm
    FROM silver.stores;


    INSERT INTO gold.dim_employees (
        employee_id, full_name, role, hire_date, salary, email
    )
    SELECT
        employee_id, full_name, role, hire_date, salary, email
    FROM silver.employees;


    INSERT INTO gold.fact_sales (
        order_item_id,
        order_id,
        customer_sk,
        product_sk,
        store_sk,
        employee_sk,
        date_key,
        payment_method,
        order_status,
        quantity,
        unit_price,
        unit_cost,
        discount_pct,
        gross_amount,
        discount_amount,
        net_amount,
        total_cost,
        margin_profit
    )
    SELECT
        i.order_item_id,
        o.order_id,
        dc.customer_sk,
        dp.product_sk,
        ds.store_sk,
        de.employee_sk,
        CASE
            WHEN o.order_date IS NULL THEN NULL
            ELSE TO_CHAR(o.order_date, 'YYYYMMDD')::INT
        END,
        o.payment_method,
        o.order_status,
        i.quantity,
        COALESCE(i.unit_price, dp.unit_price, 0.00),
        COALESCE(dp.unit_cost, 0.00),
        COALESCE(o.discount_pct, 0.0000),

        ROUND(
            i.quantity * COALESCE(i.unit_price, dp.unit_price, 0.00),
            2
        ),

        ROUND(
            i.quantity
            * COALESCE(i.unit_price, dp.unit_price, 0.00)
            * COALESCE(o.discount_pct, 0.0000),
            2
        ),

        ROUND(
            i.quantity
            * COALESCE(i.unit_price, dp.unit_price, 0.00)
            * (1 - COALESCE(o.discount_pct, 0.0000)),
            2
        ),

        ROUND(
            i.quantity * COALESCE(dp.unit_cost, 0.00),
            2
        ),

        ROUND(
            (
                i.quantity
                * COALESCE(i.unit_price, dp.unit_price, 0.00)
                * (1 - COALESCE(o.discount_pct, 0.0000))
            )
            -
            (
                i.quantity * COALESCE(dp.unit_cost, 0.00)
            ),
            2
        )

    FROM silver.order_items i
    INNER JOIN silver.orders o
        ON i.order_id = o.order_id
    INNER JOIN gold.dim_customers dc
        ON o.customer_id = dc.customer_id
    INNER JOIN gold.dim_products dp
        ON i.product_id = dp.product_id
    INNER JOIN gold.dim_stores ds
        ON o.store_id = ds.store_id
    LEFT JOIN gold.dim_employees de
        ON o.employee_id = de.employee_id;

END;
$$;


-- =============================================================================
-- SECTION 8 — GOLD INDEXES
-- =============================================================================

CREATE INDEX idx_gold_fact_sales_date_key
    ON gold.fact_sales(date_key);

CREATE INDEX idx_gold_fact_sales_customer_sk
    ON gold.fact_sales(customer_sk);

CREATE INDEX idx_gold_fact_sales_product_sk
    ON gold.fact_sales(product_sk);

CREATE INDEX idx_gold_fact_sales_store_sk
    ON gold.fact_sales(store_sk);

CREATE INDEX idx_gold_fact_sales_employee_sk
    ON gold.fact_sales(employee_sk);


-- =============================================================================
-- SECTION 9 — PROCEDURE 3: MASTER FULL REFRESH
-- =============================================================================
-- This is the procedure you normally call.
-- It clears only derived layers (Silver + Gold), then reloads them from Bronze.

CREATE OR REPLACE PROCEDURE public.refresh_warehouse()
LANGUAGE plpgsql
AS $$
BEGIN

    RAISE NOTICE 'Starting warehouse refresh...';

    TRUNCATE TABLE
        gold.fact_sales,
        gold.dim_customers,
        gold.dim_products,
        gold.dim_stores,
        gold.dim_employees,
        gold.dim_date,
        silver.order_items,
        silver.orders,
        silver.employees,
        silver.products,
        silver.stores,
        silver.customers
    RESTART IDENTITY;

    RAISE NOTICE 'Loading Silver...';
    CALL silver.load_silver();

    RAISE NOTICE 'Loading Gold...';
    CALL gold.load_gold();

    RAISE NOTICE 'Warehouse refresh completed successfully.';

END;
$$;


-- =============================================================================
-- SECTION 10 — NORMAL USAGE
-- =============================================================================
-- After this setup script has been executed once, the normal command is:
--
--     CALL public.refresh_warehouse();
--
-- Do not call silver.load_silver() repeatedly on populated Silver tables.
-- Do not rerun COPY unless you intentionally reload Bronze.


-- =============================================================================
-- SECTION 11 — SMALL VALIDATION QUERIES
-- =============================================================================

-- Check Bronze size (use this to detect accidental duplicate CSV loads)
SELECT 'bronze.customers' AS table_name, COUNT(*) AS row_count FROM bronze.customers
UNION ALL
SELECT 'bronze.orders', COUNT(*) FROM bronze.orders
UNION ALL
SELECT 'bronze.order_items', COUNT(*) FROM bronze.order_items;

-- Clean payment methods
SELECT DISTINCT payment_method
FROM silver.orders
ORDER BY payment_method;

-- Phone numbers should contain digits only
SELECT phone
FROM silver.customers
WHERE phone IS NOT NULL
  AND phone !~ '^\d+$'
LIMIT 100;

-- Emails left in Silver should be structurally valid enough for this project
SELECT email
FROM silver.customers
WHERE email IS NOT NULL
  AND email NOT LIKE '%@%.%'
LIMIT 100;

SELECT email
FROM silver.employees
WHERE email IS NOT NULL
  AND email NOT LIKE '%@%.%'
LIMIT 100;

-- Discounts must be between 0 and 1
SELECT discount_pct
FROM silver.orders
WHERE discount_pct < 0
   OR discount_pct > 1
LIMIT 100;

-- Quantities must be positive
SELECT quantity
FROM silver.order_items
WHERE quantity <= 0
LIMIT 100;

-- Fact grain: one row per order item
SELECT order_item_id, COUNT(*)
FROM gold.fact_sales
GROUP BY order_item_id
HAVING COUNT(*) > 1
LIMIT 100;

-- Small samples only — avoid SELECT * on 100k+ rows
SELECT * FROM silver.orders LIMIT 100;
SELECT * FROM gold.fact_sales LIMIT 100;

-- =============================================================================
-- END
-- =============================================================================
