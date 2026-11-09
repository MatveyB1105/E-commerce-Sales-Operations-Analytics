/*
Sales Analytics
*/
-- Выводим категории продуктов наиболее прибыльные без учета перевозок
SELECT p.product_category_name, SUM(price) as total_price_by_category FROM analytics_mart.fact_order_items o
LEFT JOIN analytics_mart.dim_products p
ON o.product_id = p.product_id
WHERE order_status IN ('delivered', 'shipped')
GROUP BY p.product_category_name
ORDER BY SUM(price) DESC;

-- Total orders
SELECT COUNT(DISTINCT order_id)
FROM analytics_mart.fact_orders;

-- Total customers
SELECT COUNT(DISTINCT dc.customer_unique_id)
FROM analytics_mart.fact_orders fo
LEFT JOIN analytics_mart.dim_customers dc
    ON fo.customer_id = dc.customer_id;

-- Total Products Sold
SELECT
    COUNT(*) AS total_products_sold
FROM analytics_mart.fact_order_items;

-- Total GMV
SELECT SUM(price) as GMV
FROM analytics_mart.fact_order_items
WHERE order_status IN ('delivered', 'shipped');

-- Total Freight
SELECT
    SUM(freight_value) AS total_freight
FROM analytics_mart.fact_order_items
WHERE order_status = 'delivered'

-- Average Order Value (delivered)

SELECT
    ROUND(
        SUM(oi.price)::numeric
        / NULLIF(COUNT(DISTINCT oi.order_id), 0),
        2
    ) AS delivered_average_order_value
FROM analytics_mart.fact_order_items oi
JOIN analytics_mart.fact_orders o
    ON oi.order_id = o.order_id
WHERE o.order_status in ('delivered', 'shipped') ;

/*
Monthly Sales Performance

Analyze monthly sales performance, customer activity, gmv, aov, compare to previous gmv
*/

WITH orders AS (
    -- Select only successfully delivered orders
    SELECT
        o.order_id,
        o.customer_id,
        o.order_purchase_timestamp

    FROM analytics_mart.fact_orders o

    WHERE o.order_status in ('delivered', 'shipped')
),

monthly_orders AS (
    -- Monthly number of delivered orders and customers
    SELECT
        DATE_TRUNC(
            'month',
            o.order_purchase_timestamp
        )::date AS month,

        COUNT(DISTINCT o.order_id) AS orders,

        COUNT(DISTINCT c.customer_unique_id) AS customers

    FROM orders o

    LEFT JOIN analytics_mart.dim_customers c
        ON o.customer_id = c.customer_id

    GROUP BY 1
),

monthly_gmv AS (
    -- Monthly GMV from delivered orders only
    SELECT
        DATE_TRUNC(
            'month',
            o.order_purchase_timestamp
        )::date AS month,

        COUNT(DISTINCT oi.order_id) AS orders_with_items,

        SUM(oi.price) AS gmv

    FROM orders o

    JOIN analytics_mart.fact_order_items oi
        ON o.order_id = oi.order_id

    GROUP BY 1
),

date_bounds AS (
    -- Find the first and last months with delivered orders
    SELECT
        MIN(DATE_TRUNC('month', order_purchase_timestamp)::date)
            AS min_month,

        MAX(DATE_TRUNC('month', order_purchase_timestamp)::date)
            AS max_month

    FROM orders
),

calendar_months AS (
    -- Generate continuous monthly calendar
    SELECT
        GENERATE_SERIES(
            min_month,
            max_month,
            INTERVAL '1 month'
        )::date AS month

    FROM date_bounds
    WHERE min_month IS NOT NULL
),

monthly_sales AS (
    SELECT
        cal.month,

        COALESCE(mo.orders, 0) AS orders,

        COALESCE(mo.customers, 0) AS customers,

        COALESCE(mg.gmv, 0) AS gmv,

        mg.gmv
            / NULLIF(mg.orders_with_items, 0) AS aov

    FROM calendar_months cal

    LEFT JOIN monthly_orders mo
        ON cal.month = mo.month

    LEFT JOIN monthly_gmv mg
        ON cal.month = mg.month
),

monthly_growth AS (
    -- Calculate previous month's GMV
    SELECT
        month,
        orders,
        customers,
        gmv,
        aov,

        LAG(gmv) OVER (
            ORDER BY month
        ) AS previous_gmv

    FROM monthly_sales
)

SELECT
    TO_CHAR(month, 'YYYY-MM') AS month,

    orders,

    customers,

    ROUND(gmv::numeric, 2) AS gmv,

    ROUND(aov::numeric, 2) AS aov,

    ROUND(previous_gmv::numeric, 2) AS previous_gmv,

    -- Month-over-Month Growth
    ROUND(
        (
            (gmv - previous_gmv)
            / NULLIF(previous_gmv, 0)
            * 100
        )::numeric,
        2
    ) AS mom_growth_percentage

FROM monthly_growth

ORDER BY month;

/*
Order Status Analysis
Determine how orders are distributed by status and what proportion of orders are successfully delivered.
*/
-- Print orders count by status
SELECT
    f.order_status,
    COUNT(DISTINCT f.order_id) AS orders_count,
    ROUND(
        100.0 * COUNT(DISTINCT f.order_id)
        / SUM(COUNT(DISTINCT f.order_id)) OVER (),
        2
    ) AS status_percentage
FROM analytics_mart.fact_orders AS f
GROUP BY f.order_status
ORDER BY orders_count DESC, f.order_status;

-- Print KPI: Total / Delivered / Canceled + rates
SELECT
    COUNT(DISTINCT f.order_id) AS total_orders,

    COUNT(DISTINCT CASE WHEN f.order_status = 'delivered'
                        THEN f.order_id END) AS delivered_orders,

    COUNT(DISTINCT CASE WHEN f.order_status = 'canceled'
                        THEN f.order_id END) AS canceled_orders,

    -- Delivered Rate = Delivered Orders / Total Orders * 100%
    ROUND(
        100.0 * COUNT(DISTINCT CASE WHEN f.order_status = 'delivered'
                                    THEN f.order_id END)
        / NULLIF(COUNT(DISTINCT f.order_id), 0),
        2
    ) AS delivered_rate,

    -- Canceled Rate = Canceled Orders / Total Orders * 100%
    ROUND(
        100.0 * COUNT(DISTINCT CASE WHEN f.order_status = 'canceled'
                                    THEN f.order_id END)
        / NULLIF(COUNT(DISTINCT f.order_id), 0),
        2
    ) AS canceled_rate
FROM analytics_mart.fact_orders AS f;

-- Print order status structure by year of purchase
SELECT
    d.calendar_year,
    f.order_status,
    COUNT(DISTINCT f.order_id) AS orders_count,
    ROUND(
        100.0 * COUNT(DISTINCT f.order_id)
        / SUM(COUNT(DISTINCT f.order_id)) OVER (PARTITION BY d.calendar_year),
        2
    ) AS status_percentage_in_year
FROM analytics_mart.fact_orders AS f
JOIN analytics_mart.dim_date AS d
    ON d.date_key = f.purchase_date
GROUP BY d.calendar_year, f.order_status
ORDER BY d.calendar_year, orders_count DESC, f.order_status;

/*
Sales by product category
*/

WITH category_sales as (
    SELECT
        p.product_category as category,
        COUNT(DISTINCT fi.order_id) as total_orders,
        COUNT(*) as products_sold,
        SUM(fi.price) as GMV,
        ROUND(AVG(fi.price), 2) as average_price,
        ROUND(
            100.0 * SUM(fi.price)
            / SUM(SUM(fi.price)) OVER (),
            2
        )  as gmv_share

    FROM analytics_mart.fact_order_items fi
    LEFT JOIN analytics_mart.dim_products p
        ON fi.product_id = p.product_id
    GROUP BY p.product_category
)
SELECT
    category,
    total_orders,
    products_sold,
    GMV,
    average_price,
    gmv_share
FROM category_sales
ORDER BY GMV DESC, category
LIMIT 10;

-- Top category with the highest average sales

WITH category_sales as (
    SELECT
        p.product_category as category,
        COUNT(DISTINCT fi.order_id) as total_orders,
        COUNT(*) as products_sold,
        SUM(fi.price) as GMV,
        ROUND(AVG(fi.price), 2) as average_price,

    FROM analytics_mart.fact_order_items fi
    LEFT JOIN analytics_mart.dim_products p
        ON fi.product_id = p.product_id
    GROUP BY p.product_category
    HAVING COUNT(DISTINCT fi.order_id) > 30
)

SELECT
    category,
    total_orders,
    GMV,
    average_price
FROM
    category_sales
ORDER by average_price DESC
LIMIT 10;

