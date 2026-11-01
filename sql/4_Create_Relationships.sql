/*

Ожидаемые таблицы:
  olist_customers_dataset
  olist_geolocation_dataset
  olist_order_items_dataset
  olist_order_payments_dataset
  olist_order_reviews_dataset
  olist_orders_dataset
  olist_products_dataset
  olist_sellers_dataset
  product_category_name_translation

Важно:
1) Run the PRE-CHECK section first. It must return no invalid keys/orphans.
2) Then run the CONSTRAINTS section.
3) Then run DIMENSIONS AND FACT VIEWS.
4) No source rows are deleted or updated by this script.
5) review_id is NOT unique in the supplied data; do not use it as a PK.
6) Geolocation is aggregated by ZIP prefix before joining, to avoid fan-out.
===============================================================================
*/

/*
0. Проверка дубликатов, дубликатов и потерянных связей
*/

-- 0.1 Проверка на NULL
SELECT 'orders.order_id' AS check_name, COUNT(*) AS invalid_rows
FROM analytics.olist_orders_dataset WHERE order_id IS NULL
UNION ALL
SELECT 'customers.customer_id', COUNT(*)
FROM analytics.olist_customers_dataset WHERE customer_id IS NULL
UNION ALL
SELECT 'products.product_id', COUNT(*)
FROM analytics.olist_products_dataset WHERE product_id IS NULL
UNION ALL
SELECT 'sellers.seller_id', COUNT(*)
FROM analytics.olist_sellers_dataset WHERE seller_id IS NULL
UNION ALL
SELECT 'order_items key columns', COUNT(*)
FROM analytics.olist_order_items_dataset
WHERE order_id IS NULL OR order_item_id IS NULL
UNION ALL
SELECT 'order_payments key columns', COUNT(*)
FROM analytics.olist_order_payments_dataset
WHERE order_id IS NULL OR payment_sequential IS NULL
ORDER BY check_name;

-- ALL ok

-- 0.2 Проверка на дупликаты
SELECT 'orders.order_id' AS check_name, COUNT(*) AS duplicate_groups
FROM (
    SELECT order_id FROM analytics.olist_orders_dataset
    GROUP BY order_id HAVING COUNT(*) > 1
) q
UNION ALL
SELECT 'customers.customer_id', COUNT(*)
FROM (
    SELECT customer_id FROM analytics.olist_customers_dataset
    GROUP BY customer_id HAVING COUNT(*) > 1
) q
UNION ALL
SELECT 'products.product_id', COUNT(*)
FROM (
    SELECT product_id FROM analytics.olist_products_dataset
    GROUP BY product_id HAVING COUNT(*) > 1
) q
UNION ALL
SELECT 'sellers.seller_id', COUNT(*)
FROM (
    SELECT seller_id FROM analytics.olist_sellers_dataset
    GROUP BY seller_id HAVING COUNT(*) > 1
) q
UNION ALL
SELECT 'order_items (order_id, order_item_id)', COUNT(*)
FROM (
    SELECT order_id, order_item_id
    FROM analytics.olist_order_items_dataset
    GROUP BY order_id, order_item_id HAVING COUNT(*) > 1
) q
UNION ALL
SELECT 'order_payments (order_id, payment_sequential)', COUNT(*)
FROM (
    SELECT order_id, payment_sequential
    FROM analytics.olist_order_payments_dataset
    GROUP BY order_id, payment_sequential HAVING COUNT(*) > 1
) q
UNION ALL
SELECT 'category translation.product_category_name', COUNT(*)
FROM (
    SELECT product_category_name
    FROM analytics.product_category_name_translation
    GROUP BY product_category_name HAVING COUNT(*) > 1
) q
ORDER BY check_name;

-- It's ok

-- 0.3 Проверка на сиротские записи
SELECT 'orders -> customers' AS relationship_name, COUNT(*) AS orphan_rows
FROM analytics.olist_orders_dataset o
LEFT JOIN analytics.olist_customers_dataset c
    ON c.customer_id = o.customer_id
WHERE o.customer_id IS NOT NULL AND c.customer_id IS NULL
UNION ALL
SELECT 'order_items -> orders', COUNT(*)
FROM analytics.olist_order_items_dataset i
LEFT JOIN analytics.olist_orders_dataset o ON o.order_id = i.order_id
WHERE o.order_id IS NULL
UNION ALL
SELECT 'order_items -> products', COUNT(*)
FROM analytics.olist_order_items_dataset i
LEFT JOIN analytics.olist_products_dataset p ON p.product_id = i.product_id
WHERE i.product_id IS NOT NULL AND p.product_id IS NULL
UNION ALL
SELECT 'order_items -> sellers', COUNT(*)
FROM analytics.olist_order_items_dataset i
LEFT JOIN analytics.olist_sellers_dataset s ON s.seller_id = i.seller_id
WHERE i.seller_id IS NOT NULL AND s.seller_id IS NULL
UNION ALL
SELECT 'order_payments -> orders', COUNT(*)
FROM analytics.olist_order_payments_dataset p
LEFT JOIN analytics.olist_orders_dataset o ON o.order_id = p.order_id
WHERE o.order_id IS NULL
UNION ALL
SELECT 'order_reviews -> orders', COUNT(*)
FROM analytics.olist_order_reviews_dataset r
LEFT JOIN analytics.olist_orders_dataset o ON o.order_id = r.order_id
WHERE r.order_id IS NOT NULL AND o.order_id IS NULL
UNION ALL
SELECT 'products -> category translation', COUNT(*)
FROM analytics.olist_products_dataset p
LEFT JOIN analytics.product_category_name_translation t
    ON t.product_category_name = p.product_category_name
WHERE p.product_category_name IS NOT NULL
  AND t.product_category_name IS NULL
ORDER BY relationship_name;

-- products -> category translation: 13 пропущено

-- Проверка уникальных категорий без перевода

SELECT
    p.product_category_name,
    COUNT(*) AS products_count
FROM analytics.olist_products_dataset p
LEFT JOIN analytics.product_category_name_translation t
    ON t.product_category_name = p.product_category_name
WHERE p.product_category_name IS NOT NULL
  AND t.product_category_name IS NULL
GROUP BY p.product_category_name
ORDER BY products_count DESC;
-- Выводит  пропущенные категории product_category_name
-- Идея: можно в product_category_name_english для таких категорий добавить untranslated

-- 0.4 Проверка дупликатов комбинации review_id + order_id так как review_id имеет дупликаты
SELECT review_id, order_id, COUNT(*) AS rows_per_pair
FROM analytics.olist_order_reviews_dataset
GROUP BY review_id, order_id
HAVING COUNT(*) > 1
ORDER BY rows_per_pair DESC; --ok

-- 0.5 Category mapping quality: ideally no duplicate mapping keys.
SELECT
    product_category_name,
    COUNT(*) AS mapping_rows,
    COUNT(DISTINCT product_category_name_english) AS english_variants
FROM analytics.product_category_name_translation
GROUP BY product_category_name
HAVING COUNT(*) > 1
ORDER BY mapping_rows DESC; -- ok

/*
Предобработка данных
*/

--  Добавляем к product_category_name "untranslated"
BEGIN;

INSERT INTO analytics.product_category_name_translation (
    product_category_name,
    product_category_name_english
)
SELECT DISTINCT
    p.product_category_name,
    '[untranslated] ' || p.product_category_name
FROM analytics.olist_products_dataset p
WHERE p.product_category_name IS NOT NULL
  AND NOT EXISTS (
      SELECT 1
      FROM analytics.product_category_name_translation t
      WHERE t.product_category_name = p.product_category_name
  );

COMMIT;

-- Создаем виртуальную таблицу для "странных" дат
CREATE OR REPLACE VIEW analytics.v_orders_clean AS

SELECT
    o.*,

    -- Очищенная дата передачи перевозчику
    CASE
        WHEN order_delivered_carrier_date < order_approved_at
            THEN NULL
        ELSE order_delivered_carrier_date
    END AS delivered_carrier_date_clean,

    -- Очищенная дата доставки покупателю
    CASE
        WHEN order_delivered_customer_date < order_delivered_carrier_date
            THEN NULL
        ELSE order_delivered_customer_date
    END AS delivered_customer_date_clean,

    -- Флаг качества дат
    CASE
        WHEN order_delivered_carrier_date < order_approved_at
          OR order_delivered_customer_date < order_delivered_carrier_date
            THEN 'date_anomaly'
        ELSE 'valid'
    END AS date_quality_status

FROM analytics.olist_orders_dataset o;


/*=============================================================================
  1. Настройка первичных ключей и ссылочной целостности
=============================================================================*/

DO $$
BEGIN;

-- 1. ORDERS
ALTER TABLE analytics.olist_orders_dataset
ADD CONSTRAINT pk_orders
PRIMARY KEY (order_id);


-- 2. CUSTOMERS
ALTER TABLE analytics.olist_customers_dataset
ADD CONSTRAINT pk_customers
PRIMARY KEY (customer_id);


-- 3. PRODUCTS
ALTER TABLE analytics.olist_products_dataset
ADD CONSTRAINT pk_products
PRIMARY KEY (product_id);


-- 4. SELLERS
ALTER TABLE analytics.olist_sellers_dataset
ADD CONSTRAINT pk_sellers
PRIMARY KEY (seller_id);


-- 5. ORDER ITEMS
ALTER TABLE analytics.olist_order_items_dataset
ADD CONSTRAINT pk_order_items
PRIMARY KEY (order_id, order_item_id);


-- 6. ORDER PAYMENTS
ALTER TABLE analytics.olist_order_payments_dataset
ADD CONSTRAINT pk_order_payments
PRIMARY KEY (order_id, payment_sequential);


-- 7. ORDER REVIEWS
ALTER TABLE analytics.olist_order_reviews_dataset
ADD CONSTRAINT pk_order_reviews
PRIMARY KEY (review_id, order_id);
-- (review_id, order_id) - PK

-- 8. CATEGORY TRANSLATION
ALTER TABLE analytics.product_category_name_translation
ADD CONSTRAINT pk_category_translation
PRIMARY KEY (product_category_name);

COMMIT;
END $$;

-- Foreign Key
BEGIN;
-- ORDERS -> CUSTOMERS
ALTER TABLE analytics.olist_orders_dataset
ADD CONSTRAINT fk_orders_customers
FOREIGN KEY (customer_id)
REFERENCES analytics.olist_customers_dataset(customer_id);

-- ORDER ITEMS -> ORDERS
ALTER TABLE analytics.olist_order_items_dataset
ADD CONSTRAINT fk_items_orders
FOREIGN KEY (order_id)
REFERENCES analytics.olist_orders_dataset(order_id);

-- ORDER ITEMS -> PRODUCTS
ALTER TABLE analytics.olist_order_items_dataset
ADD CONSTRAINT fk_items_products
FOREIGN KEY (product_id)
REFERENCES analytics.olist_products_dataset(product_id);

-- ORDER ITEMS -> SELLERS
ALTER TABLE analytics.olist_order_items_dataset
ADD CONSTRAINT fk_items_sellers
FOREIGN KEY (seller_id)
REFERENCES analytics.olist_sellers_dataset(seller_id);

-- PAYMENTS -> ORDERS
ALTER TABLE analytics.olist_order_payments_dataset
ADD CONSTRAINT fk_payments_orders
FOREIGN KEY (order_id)
REFERENCES analytics.olist_orders_dataset(order_id);

-- REVIEWS -> ORDERS
ALTER TABLE analytics.olist_order_reviews_dataset
ADD CONSTRAINT fk_reviews_orders
FOREIGN KEY (order_id)
REFERENCES analytics.olist_orders_dataset(order_id);

-- PRODUCTS -> CATEGORY TRANSLATION
ALTER TABLE analytics.olist_products_dataset
ADD CONSTRAINT fk_products_categories
FOREIGN KEY (product_category_name)
REFERENCES analytics.product_category_name_translation(product_category_name);
COMMIT;


