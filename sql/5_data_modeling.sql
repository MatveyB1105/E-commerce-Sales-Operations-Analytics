/*
  Создать отдельную аналитическую схему analytics_mart поверх подготовленных
  исходных данных из схемы analytics.

  Важно: должно существовать представление analytics.v_orders_clean из 4 шага

  ДЕТАЛИЗАЦИЯ
  fact_order_items: одна строка = одна товарная позиция в заказе;
  fact_orders: одна строка = один заказ;
  fact_payments: одна строка = одна платежная запись;
  fact_reviews: одна строка = одна запись отзыва на заказ
                     (ключ review_id + order_id).

*/

--0. Создание аналитической схемы
CREATE SCHEMA IF NOT EXISTS analytics_mart;


/*
  1. DIMENSION TABLES (DIMENSIONS)

  Dimensions содержат описательные атрибуты, по которым мы фильтруем,
  группируем и сравниваем показатели: покупатель, товар, продавец, дата,
  географическое расположение.
*/

-- 1.1. dim_geolocation
-- 1 строка - 1 ZIP префикс
CREATE OR REPLACE VIEW analytics_mart.dim_geolocation AS
SELECT
    g.geolocation_zip_code_prefix AS zip_code_prefix,
    AVG(g.geolocation_lat)        AS latitude,
    AVG(g.geolocation_lng)        AS longitude,
    COUNT(*)                      AS source_records,
    COUNT(DISTINCT g.geolocation_city)  AS distinct_cities,
    COUNT(DISTINCT g.geolocation_state) AS distinct_states
FROM analytics.olist_geolocation_dataset AS g
GROUP BY g.geolocation_zip_code_prefix;

COMMENT ON VIEW analytics_mart.dim_geolocation IS
'Одна строка на ZIP prefix; координаты усреднены для предотвращения fan-out при JOIN.';


-- 1.2. dim_customers
-- 1 строка - 1 customer_id
CREATE OR REPLACE VIEW analytics_mart.dim_customers AS
SELECT
    c.customer_id,
    c.customer_unique_id,
    c.customer_zip_code_prefix,
    c.customer_city,
    c.customer_state,
    g.latitude  AS customer_latitude,
    g.longitude AS customer_longitude
FROM analytics.olist_customers_dataset AS c
LEFT JOIN analytics_mart.dim_geolocation AS g
    ON g.zip_code_prefix = c.customer_zip_code_prefix;

COMMENT ON VIEW analytics_mart.dim_customers IS
'Одна строка на customer_id; customer_unique_id используется для аналитики повторных покупок.';


/*
  1.3. dim_products: одна строка = один product_id.
*/
CREATE OR REPLACE VIEW analytics_mart.dim_products AS
SELECT
    p.product_id,
    p.product_category_name,
    COALESCE(
        t.product_category_name_english,
        '[untranslated] ' || p.product_category_name,
        '[unknown category]'
    ) AS product_category,
    p.product_name_lenght,
    p.product_description_lenght,
    p.product_photos_qty,
    p.product_weight_g,
    p.product_length_cm,
    p.product_height_cm,
    p.product_width_cm
FROM analytics.olist_products_dataset AS p
LEFT JOIN analytics.product_category_name_translation AS t
    ON t.product_category_name = p.product_category_name;

COMMENT ON VIEW analytics_mart.dim_products IS
'Одна строка на product_id; содержит характеристики товара и название категории с fallback для пропущенного перевода.';


/*
1.4. dim_sellers одна строка = один seller_id.
*/
CREATE OR REPLACE VIEW analytics_mart.dim_sellers AS
SELECT
    s.seller_id,
    s.seller_zip_code_prefix,
    s.seller_city,
    s.seller_state,
    g.latitude  AS seller_latitude,
    g.longitude AS seller_longitude
FROM analytics.olist_sellers_dataset AS s
LEFT JOIN analytics_mart.dim_geolocation AS g
    ON g.zip_code_prefix = s.seller_zip_code_prefix;

COMMENT ON VIEW analytics_mart.dim_sellers IS
'Одна строка на seller_id; содержит адресные атрибуты продавца и агрегированные координаты ZIP prefix.';


/*
  1.5. dim_date одна строка = один календарный день.
*/
CREATE OR REPLACE VIEW analytics_mart.dim_date AS
WITH all_order_dates AS (
    SELECT order_purchase_timestamp::date AS date_value
    FROM analytics.olist_orders_dataset
    WHERE order_purchase_timestamp IS NOT NULL

    UNION ALL
    SELECT order_approved_at::date
    FROM analytics.olist_orders_dataset
    WHERE order_approved_at IS NOT NULL

    UNION ALL
    SELECT order_delivered_carrier_date::date
    FROM analytics.olist_orders_dataset
    WHERE order_delivered_carrier_date IS NOT NULL

    UNION ALL
    SELECT order_delivered_customer_date::date
    FROM analytics.olist_orders_dataset
    WHERE order_delivered_customer_date IS NOT NULL

    UNION ALL
    SELECT order_estimated_delivery_date::date
    FROM analytics.olist_orders_dataset
    WHERE order_estimated_delivery_date IS NOT NULL
),
date_bounds AS (
    SELECT
        MIN(date_value) AS min_date,
        MAX(date_value) AS max_date
    FROM all_order_dates
),
calendar AS (
    SELECT gs.date_value::date AS date_key
    FROM date_bounds AS b
    CROSS JOIN LATERAL generate_series(
        b.min_date::timestamp,
        b.max_date::timestamp,
        INTERVAL '1 day'
    ) AS gs(date_value)
)
SELECT
    c.date_key,
    EXTRACT(YEAR FROM c.date_key)::int       AS calendar_year,
    EXTRACT(QUARTER FROM c.date_key)::int    AS quarter_number,
    EXTRACT(MONTH FROM c.date_key)::int      AS month_number,
    TO_CHAR(c.date_key, 'YYYY-MM')           AS year_month,
    TO_CHAR(c.date_key, 'FMMonth')           AS month_name,
    EXTRACT(ISOYEAR FROM c.date_key)::int    AS iso_year,
    EXTRACT(WEEK FROM c.date_key)::int       AS iso_week_number,
    EXTRACT(ISODOW FROM c.date_key)::int     AS iso_day_of_week,
    TO_CHAR(c.date_key, 'FMDay')             AS day_name,
    (EXTRACT(ISODOW FROM c.date_key) IN (6, 7)) AS is_weekend,
    (EXTRACT(DAY FROM c.date_key) = 1)       AS is_month_start,
    (c.date_key = (DATE_TRUNC('month', c.date_key)
                   + INTERVAL '1 month - 1 day')::date) AS is_month_end
FROM calendar AS c;

COMMENT ON VIEW analytics_mart.dim_date IS
'Календарь на каждый день в диапазоне дат жизненного цикла заказов; ISO-неделя начинается с понедельника.';


/*
  2. FACT TABLES (FACTS)

  Fact Tables содержат измеряемые события и показатели.
*/

/*
  2.1. fact_order_items
  одна строка = одна товарная позиция в заказе.
  Уникальный ключ исходного набора: (order_id, order_item_id).
  - GMV = SUM(price) по выбранным правилам включения заказов;
  - Units Sold = COUNT(*) или COUNT(order_item_id) на уровне позиций;
  - продажи по товарам, категориям, продавцам и покупателям;
  - freight = SUM(freight_value).

*/
CREATE OR REPLACE VIEW analytics_mart.fact_order_items AS
SELECT
    -- Degenerate/business keys
    oi.order_id,
    oi.order_item_id,

    -- Foreign keys to dimensions
    oi.product_id,
    oi.seller_id,
    o.customer_id,

    -- Order date attributes
    o.order_purchase_timestamp,
    o.order_purchase_timestamp::date AS purchase_date,

    -- Order context
    o.order_status,

    -- Measures at item grain
    oi.price,
    oi.freight_value,
    (oi.price + oi.freight_value) AS item_total_value
FROM analytics.olist_order_items_dataset AS oi
LEFT JOIN analytics.v_orders_clean AS o
    ON o.order_id = oi.order_id;

COMMENT ON VIEW analytics_mart.fact_order_items IS
'Одна строка на товарную позицию (order_id + order_item_id); основа Sales и Product Analytics.';


/*
  2.2. fact_orders

  одна строка = один заказ.
  Уникальный ключ: order_id.

  Основное использование:
  - статусная аналитика заказов;
  - время одобрения;
  - время подготовки до передачи перевозчику;
  - время доставки перевозчиком;
  - полное время от покупки до доставки;
  - on-time / late delivery.

  delivery_delay_days:
  - положительное значение = доставлено позже ожидаемой даты;
  - 0 = в ожидаемую дату;
  - отрицательное значение = раньше ожидаемой даты;
  - NULL = нет фактической или ожидаемой даты доставки.
*/
CREATE OR REPLACE VIEW analytics_mart.fact_orders AS
SELECT
    -- Keys
    o.order_id,
    o.customer_id,

    -- Status
    o.order_status,

    -- Original timestamps
    o.order_purchase_timestamp,
    o.order_approved_at,
    o.order_delivered_carrier_date,
    o.order_delivered_customer_date,
    o.order_estimated_delivery_date,

    -- Cleaned timestamps
    o.delivered_carrier_date_clean,
    o.delivered_customer_date_clean,

    -- Date keys for role-playing date relationships in BI
    o.order_purchase_timestamp::date       AS purchase_date,
    o.order_approved_at::date              AS approval_date,
    o.delivered_carrier_date_clean::date   AS carrier_date,
    o.delivered_customer_date_clean::date  AS delivery_date,
    o.order_estimated_delivery_date::date AS estimated_delivery_date,

    -- Data quality status: distinguish missing delivery date from date anomaly
    CASE
        WHEN o.order_delivered_carrier_date < o.order_approved_at
          OR o.order_delivered_customer_date < o.order_delivered_carrier_date
            THEN 'date_anomaly'
        WHEN o.order_status = 'delivered'
         AND o.delivered_customer_date_clean IS NULL
            THEN 'missing_delivery_date'
        ELSE 'valid'
    END AS date_quality_status,

    -- Lifecycle durations in hours
    CASE
        WHEN o.order_approved_at >= o.order_purchase_timestamp
        THEN EXTRACT(EPOCH FROM (
            o.order_approved_at - o.order_purchase_timestamp
        )) / 3600.0
        ELSE NULL
    END AS approval_hours,

    CASE
        WHEN o.delivered_carrier_date_clean IS NOT NULL
         AND o.order_approved_at IS NOT NULL
         AND o.delivered_carrier_date_clean >= o.order_approved_at
        THEN EXTRACT(EPOCH FROM (
            o.delivered_carrier_date_clean - o.order_approved_at
        )) / 3600.0
        ELSE NULL
    END AS preparation_hours,

    CASE
        WHEN o.delivered_customer_date_clean IS NOT NULL
         AND o.delivered_carrier_date_clean IS NOT NULL
         AND o.delivered_customer_date_clean >= o.delivered_carrier_date_clean
        THEN EXTRACT(EPOCH FROM (
            o.delivered_customer_date_clean - o.delivered_carrier_date_clean
        )) / 3600.0
        ELSE NULL
    END AS shipping_hours,

    CASE
        WHEN o.delivered_customer_date_clean IS NOT NULL
         AND o.delivered_customer_date_clean >= o.order_purchase_timestamp
        THEN EXTRACT(EPOCH FROM (
            o.delivered_customer_date_clean - o.order_purchase_timestamp
        )) / 3600.0
        ELSE NULL
    END AS total_delivery_hours,

    -- Delivery delay in calendar days (actual date - estimated date)
    CASE
        WHEN o.delivered_customer_date_clean IS NOT NULL
         AND o.order_estimated_delivery_date IS NOT NULL
        THEN o.delivered_customer_date_clean::date
             - o.order_estimated_delivery_date::date
        ELSE NULL
    END AS delivery_delay_days,

    -- NULL means the delivery result cannot be evaluated
    CASE
        WHEN o.delivered_customer_date_clean IS NULL
          OR o.order_estimated_delivery_date IS NULL
            THEN NULL
        WHEN o.delivered_customer_date_clean::date
             <= o.order_estimated_delivery_date::date
            THEN TRUE
        ELSE FALSE
    END AS is_on_time_delivery,

    (o.order_status = 'delivered') AS is_delivered_order
FROM analytics.v_orders_clean AS o;

COMMENT ON VIEW analytics_mart.fact_orders IS
'Одна строка на order_id; основа Order Status и Logistics/Operations Analytics.';


/*
  2.3. fact_payments

  одна строка = одна платёжная запись.
  Уникальный ключ: (order_id, payment_sequential).

  Ограничение источника:
  В таблице Olist payments нет отдельной даты фактического проведения платежа.
  Поэтому order_purchase_date — это дата оформления заказа, а не дата оплаты.

*/
CREATE OR REPLACE VIEW analytics_mart.fact_payments AS
SELECT
    p.order_id,
    p.payment_sequential,

    o.customer_id,
    o.order_status,
    o.order_purchase_timestamp,
    o.order_purchase_timestamp::date AS order_purchase_date,

    p.payment_type,
    p.payment_installments,
    p.payment_value
FROM analytics.olist_order_payments_dataset AS p
LEFT JOIN analytics.olist_orders_dataset AS o
    ON o.order_id = p.order_id;

COMMENT ON VIEW analytics_mart.fact_payments IS
'Одна строка на платежную запись (order_id + payment_sequential); дата заказа не является датой фактического платежа.';


/*
  2.4. fact_reviews

  одна строка = одна запись отзыва для конкретного заказа.
  Уникальный ключ: (review_id, order_id).

  Добавляем customer_id и дату покупки из orders, чтобы можно было связывать
  отзывы с покупателями и анализировать оценки с учётом заказа.
*/
CREATE OR REPLACE VIEW analytics_mart.fact_reviews AS
SELECT
    r.review_id,
    r.order_id,

    o.customer_id,
    o.order_status,
    o.order_purchase_timestamp,
    o.order_purchase_timestamp::date AS order_purchase_date,

    r.review_score,
    r.review_comment_title,
    r.review_comment_message,
    r.review_creation_date,
    r.review_answer_timestamp
FROM analytics.olist_order_reviews_dataset AS r
LEFT JOIN analytics.olist_orders_dataset AS o
    ON o.order_id = r.order_id;

COMMENT ON VIEW analytics_mart.fact_reviews IS
'Одна строка на пару review_id + order_id; основа Review/Satisfaction Analytics.';


/*
  3. QUICK MODEL INVENTORY
  Проверка недавно созданных views.
*/

-- Список представлений аналитической схемы.
SELECT table_name
FROM information_schema.views
WHERE table_schema = 'analytics_mart'
ORDER BY table_name; -- Вывод 9 таблиц




/*
  4. Валидация данных
*/



/*
  4.1 Проверка уникальности id в Fact Tables.
*/

-- fact_order_items: составной ключ order_id + order_item_id.
SELECT order_id, order_item_id, COUNT(*) AS rows_count
FROM analytics_mart.fact_order_items
GROUP BY order_id, order_item_id
HAVING COUNT(*) > 1; -- 0

-- fact_orders: order_id.
SELECT order_id, COUNT(*) AS rows_count
FROM analytics_mart.fact_orders
GROUP BY order_id
HAVING COUNT(*) > 1; -- 0

-- fact_payments: составной ключ order_id + payment_sequential.
SELECT order_id, payment_sequential, COUNT(*) AS rows_count
FROM analytics_mart.fact_payments
GROUP BY order_id, payment_sequential
HAVING COUNT(*) > 1; -- 0

-- fact_reviews: составной ключ review_id + order_id.
SELECT review_id, order_id, COUNT(*) AS rows_count
FROM analytics_mart.fact_reviews
GROUP BY review_id, order_id
HAVING COUNT(*) > 1; -- 0


/*
  4.2 Проверка уникальности Dimensions.
*/
SELECT
    'dim_customers' AS dimension_name,
    COUNT(*) AS rows_count,
    COUNT(DISTINCT customer_id) AS unique_keys
FROM analytics_mart.dim_customers
UNION ALL
SELECT
    'dim_products',
    COUNT(*),
    COUNT(DISTINCT product_id)
FROM analytics_mart.dim_products
UNION ALL
SELECT
    'dim_sellers',
    COUNT(*),
    COUNT(DISTINCT seller_id)
FROM analytics_mart.dim_sellers
UNION ALL
SELECT
    'dim_geolocation',
    COUNT(*),
    COUNT(DISTINCT zip_code_prefix)
FROM analytics_mart.dim_geolocation
UNION ALL
SELECT
    'dim_date',
    COUNT(*),
    COUNT(DISTINCT date_key)
FROM analytics_mart.dim_date
ORDER BY dimension_name;
-- ok

/*
  4.3 Проверка отсутствующих Dimension matches.
*/
SELECT
    'missing_products' AS check_name,
    COUNT(*) AS unmatched_rows
FROM analytics_mart.fact_order_items AS f
LEFT JOIN analytics_mart.dim_products AS d
    ON d.product_id = f.product_id
WHERE d.product_id IS NULL

UNION ALL
SELECT
    'missing_sellers',
    COUNT(*)
FROM analytics_mart.fact_order_items AS f
LEFT JOIN analytics_mart.dim_sellers AS d
    ON d.seller_id = f.seller_id
WHERE d.seller_id IS NULL

UNION ALL
SELECT
    'missing_customers_in_orders',
    COUNT(*)
FROM analytics_mart.fact_orders AS f
LEFT JOIN analytics_mart.dim_customers AS d
    ON d.customer_id = f.customer_id
WHERE d.customer_id IS NULL

UNION ALL
SELECT
    'missing_customers_in_items',
    COUNT(*)
FROM analytics_mart.fact_order_items AS f
LEFT JOIN analytics_mart.dim_customers AS d
    ON d.customer_id = f.customer_id
WHERE d.customer_id IS NULL
ORDER BY check_name;

-- ok

/*
  4.4 Тест на fan-out при JOIN товарных позиций с Dimensions.
*/
SELECT
    COUNT(*) AS rows_after_join,
    COUNT(DISTINCT (f.order_id, f.order_item_id)) AS unique_items,
    SUM(f.price) AS total_gmv_after_join
FROM analytics_mart.fact_order_items AS f
LEFT JOIN analytics_mart.dim_products AS p
    ON p.product_id = f.product_id
LEFT JOIN analytics_mart.dim_sellers AS s
    ON s.seller_id = f.seller_id
LEFT JOIN analytics_mart.dim_customers AS c
    ON c.customer_id = f.customer_id;


/*
  4.5 Контроль временных интервалов в fact_orders.
*/

SELECT
    COUNT(*) FILTER (WHERE approval_hours < 0)      AS negative_approval_hours,
    COUNT(*) FILTER (WHERE preparation_hours < 0)    AS negative_preparation_hours,
    COUNT(*) FILTER (WHERE shipping_hours < 0)       AS negative_shipping_hours,
    COUNT(*) FILTER (WHERE total_delivery_hours < 0) AS negative_total_delivery_hours
FROM analytics_mart.fact_orders;
-- ok

/*
  4.6. Проверка категорий: сколько продуктов имеют fallback-названия.
  При наличии исходной категории без перевода она должна быть явно помечена.
*/
SELECT
    COUNT(*) FILTER (
        WHERE product_category LIKE '[untranslated] %'
    ) AS untranslated_category_products,
    COUNT(*) FILTER (
        WHERE product_category = '[unknown category]'
    ) AS unknown_category_products
FROM analytics_mart.dim_products;
-- untranslated_category_products - 13, unknown_category_products - 610

