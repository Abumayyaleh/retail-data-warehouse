# Diagram sources

The SVG files render directly in the README. These Mermaid definitions provide editable versions of the same architecture and relationships.

## Architecture

```mermaid
flowchart LR
    CSV[Six retail CSV files] -->|Separate COPY or client-side copy| B[Bronze: raw TEXT tables]
    B -->|silver.load_silver| S[Silver: six clean typed tables]
    S -->|gold.load_gold| G[Gold: five dimensions and fact_sales]
    G --> A[SQL analysis / future BI dashboard]
    R[public.refresh_warehouse] -.->|Truncate and reload Silver then Gold| S
    R -.-> G
```

## Star schema

All fact foreign keys are nullable in the DDL. The loader requires customer, product, and store matches; employee and date keys can remain null.

```mermaid
erDiagram
    dim_customers |o--o{ fact_sales : customer_sk
    dim_products |o--o{ fact_sales : product_sk
    dim_stores |o--o{ fact_sales : store_sk
    dim_employees |o--o{ fact_sales : employee_sk
    dim_date |o--o{ fact_sales : date_key
    fact_sales {
        bigint sales_fact_id PK
        int order_item_id UK
        int order_id
        int customer_sk FK
        int product_sk FK
        int store_sk FK
        int employee_sk FK
        int date_key FK
        int quantity
        numeric gross_amount
        numeric discount_amount
        numeric net_amount
        numeric total_cost
        numeric margin_profit
    }
```
