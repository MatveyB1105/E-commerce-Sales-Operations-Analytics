
-- Проверка на дупликаты из таблицы заказы
SELECT
    order_id,
    COUNT(*) AS duplicate_count
FROM analytics.olist_orders_dataset
GROUP BY order_id
HAVING COUNT(*) > 1
ORDER BY duplicate_count DESC;
-- Вывод 0 дупликатов

-- Проверка на дупликаты из таблицы отзывы
SELECT review_id, COUNT(*) as duplicates
FROM analytics.olist_order_reviews_dataset
GROUP BY review_id
HAVING COUNT(*) > 1
ORDER BY duplicates DESC;
-- Вывод 561 review_id имели дупликаты

-- Проверка на дупликаты из таблицы покупатели
SELECT customer_unique_id, COUNT(*) as duplicates
FROM analytics.olist_customers_dataset
GROUP BY customer_unique_id
HAVING COUNT(*) > 1
ORDER BY duplicates DESC;
-- Вывод 2997 имеют дупликаты (если заменить customer_unique_id на customer_id то таблица будет иметь 0 дупликатов)
-- customer_id, customer_unique_id - 0 дупликатов

-- Проверка на дупликаты из таблицы продукты
SELECT product_id, COUNT(*) as duplicates
FROM analytics.olist_products_dataset
GROUP BY product_id
HAVING COUNT(*) > 1
ORDER BY duplicates DESC;
-- 0 дупликатов

-- Проверка на дупликаты из таблицы продавцы
SELECT seller_id, COUNT(*) as duplicates
FROM analytics.olist_sellers_dataset
GROUP BY seller_id
HAVING COUNT(*) > 1
ORDER BY duplicates DESC;
-- 0 дупликатов

-- Проверка на дупликаты из таблицы заказы
SELECT order_id, COUNT(*) as duplicates
FROM analytics.olist_orders_dataset
GROUP BY order_id
HAVING COUNT(*) > 1
ORDER BY duplicates DESC;
-- 0

/* Проверка на NULL в ключах */

-- ORDERS
SELECT COUNT(*)
FROM analytics.olist_orders_dataset
WHERE order_id IS NULL OR customer_id IS NULL; -- 0

-- ITEMS
SELECT COUNT(*)
FROM analytics.olist_order_items_dataset
WHERE order_id IS NULL OR order_item_id IS NULL
 OR product_id IS NULL OR seller_id IS NULL; -- 0

-- PAYMENTS
SELECT COUNT(*)
FROM analytics.olist_order_payments_dataset
WHERE order_id IS NULL OR payment_sequential IS NULL; -- 0

-- CUSTOMERS
SELECT COUNT(*) AS invalid_rows
FROM analytics.olist_customers_dataset
WHERE customer_id IS NULL
   OR customer_unique_id IS NULL; -- 0

-- PRODUCTS
SELECT COUNT(*) AS invalid_rows
FROM analytics.olist_products_dataset
WHERE product_id IS NULL; -- 0

-- SELLERS
SELECT COUNT(*) AS invalid_rows
FROM analytics.olist_sellers_dataset
WHERE seller_id IS NULL; -- 0

-- REVIEWS
SELECT COUNT(*) AS invalid_rows
FROM analytics.olist_order_reviews_dataset
WHERE review_id IS NULL
   OR order_id IS NULL; -- 0

-- ORDER ITEMS
SELECT COUNT(*) AS invalid_rows
FROM analytics.olist_order_items_dataset
WHERE order_id IS NULL
   OR order_item_id IS NULL
   OR product_id IS NULL
   OR seller_id IS NULL; -- 0

-- PAYMENTS
SELECT COUNT(*) AS invalid_rows
FROM analytics.olist_order_payments_dataset
WHERE order_id IS NULL
   OR payment_sequential IS NULL; -- 0

-- GEOLOCATION
SELECT COUNT(*) AS invalid_rows
FROM analytics.olist_geolocation_dataset
WHERE geolocation_zip_code_prefix IS NULL; -- 0

-- CATEGORY TRANSLATION
SELECT COUNT(*) AS invalid_rows
FROM analytics.product_category_name_translation
WHERE product_category_name IS NULL
   OR product_category_name_english IS NULL; -- 0

/* Инварианты времени в заказах */

SELECT COUNT(*) AS delivered_before_purchase
FROM analytics.olist_orders_dataset
WHERE order_delivered_customer_date < order_purchase_timestamp; -- 0

SELECT COUNT(*) AS delivered_status_no_date
FROM analytics.olist_orders_dataset
WHERE order_status = 'delivered' AND order_delivered_customer_date IS NULL; -- 8

/* Проверка диапазонов числовых значений */

SELECT *
FROM analytics.olist_order_items_dataset
WHERE order_item_id <= 0
   OR price < 0
   OR freight_value < 0; -- ok

SELECT *
FROM analytics.olist_order_payments_dataset
WHERE payment_sequential <= 0
   OR payment_installments <= 0
   OR payment_value < 0; -- 2 заказа payment_installments = 0 (order_id = 744bade1fcf9ff3f31d860ace076d422, 1a57108394169c0b47d8f876acc9ba2d)

SELECT *
FROM analytics.olist_order_reviews_dataset
WHERE review_score NOT BETWEEN 1 AND 5; -- ok

SELECT *
FROM analytics.olist_products_dataset
WHERE product_name_lenght < 0
   OR product_description_lenght < 0
   OR product_photos_qty < 0
   OR product_weight_g < 0
   OR product_length_cm < 0
   OR product_height_cm < 0
   OR product_width_cm < 0; -- ok

/* Анализ дупликатов отызвов */

SELECT
    review_id,
    COUNT(*) AS rows_count,
    COUNT(DISTINCT order_id) AS different_orders,
    COUNT(DISTINCT review_score) AS different_scores
FROM analytics.olist_order_reviews_dataset
GROUP BY review_id
HAVING COUNT(*) > 1
ORDER BY rows_count DESC;

-- Запрос показал что есть один и тот же отзыв (по ID) на разные заказы, different scores везде > 1

SELECT
    review_id,
    order_id,
    COUNT(*) AS duplicate_count
FROM analytics.olist_order_reviews_dataset
GROUP BY review_id, order_id
HAVING COUNT(*) > 1
ORDER BY duplicate_count DESC; -- дупликатов не показал


