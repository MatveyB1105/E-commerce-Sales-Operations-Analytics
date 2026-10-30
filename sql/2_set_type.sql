BEGIN;

-- 1. КЛИЕНТЫ
ALTER TABLE analytics.olist_customers_dataset
    ALTER COLUMN customer_zip_code_prefix TYPE VARCHAR(10),
    ALTER COLUMN customer_state TYPE VARCHAR(2);

-- 2. ГЕОЛОКАЦИЯ
ALTER TABLE analytics.olist_geolocation_dataset
    ALTER COLUMN geolocation_zip_code_prefix TYPE VARCHAR(10),
    ALTER COLUMN geolocation_lat TYPE DOUBLE PRECISION USING NULLIF(trim(geolocation_lat), '')::double precision,
    ALTER COLUMN geolocation_lng TYPE DOUBLE PRECISION USING NULLIF(trim(geolocation_lng), '')::double precision,
    ALTER COLUMN geolocation_state TYPE VARCHAR(2);

-- 3. ПОЗИЦИИ ЗАКАЗОВ
ALTER TABLE analytics.olist_order_items_dataset
    ALTER COLUMN order_item_id TYPE SMALLINT USING NULLIF(trim(order_item_id), '')::smallint,
    ALTER COLUMN shipping_limit_date TYPE TIMESTAMP USING NULLIF(trim(shipping_limit_date), '')::timestamp,
    ALTER COLUMN price TYPE NUMERIC(10,2) USING NULLIF(trim(price), '')::numeric,
    ALTER COLUMN freight_value TYPE NUMERIC(10,2) USING NULLIF(trim(freight_value), '')::numeric;

-- 4. ПЛАТЕЖИ
ALTER TABLE analytics.olist_order_payments_dataset
    ALTER COLUMN payment_sequential TYPE SMALLINT USING NULLIF(trim(payment_sequential), '')::smallint,
    ALTER COLUMN payment_type TYPE VARCHAR(20),
    ALTER COLUMN payment_installments TYPE SMALLINT USING NULLIF(trim(payment_installments), '')::smallint,
    ALTER COLUMN payment_value TYPE NUMERIC(10,2) USING NULLIF(trim(payment_value), '')::numeric;

-- 5. ПРОДАВЦЫ
ALTER TABLE analytics.olist_sellers_dataset
    ALTER COLUMN seller_zip_code_prefix TYPE VARCHAR(10),
    ALTER COLUMN seller_state TYPE VARCHAR(2);

-- 6. ЗАКАЗЫ
ALTER TABLE analytics.olist_orders_dataset
    ALTER COLUMN order_status TYPE VARCHAR(20),
    ALTER COLUMN order_purchase_timestamp TYPE TIMESTAMP USING NULLIF(trim(order_purchase_timestamp), '')::timestamp,
    ALTER COLUMN order_approved_at TYPE TIMESTAMP USING NULLIF(trim(order_approved_at), '')::timestamp,
    ALTER COLUMN order_delivered_carrier_date TYPE TIMESTAMP USING NULLIF(trim(order_delivered_carrier_date), '')::timestamp,
    ALTER COLUMN order_delivered_customer_date TYPE TIMESTAMP USING NULLIF(trim(order_delivered_customer_date), '')::timestamp,
    ALTER COLUMN order_estimated_delivery_date TYPE TIMESTAMP USING NULLIF(trim(order_estimated_delivery_date), '')::timestamp;

-- 7. ОТЗЫВЫ
ALTER TABLE analytics.olist_order_reviews_dataset
    ALTER COLUMN review_score TYPE SMALLINT USING NULLIF(trim(review_score), '')::smallint,
    ALTER COLUMN review_comment_title TYPE TEXT USING NULLIF(review_comment_title, ''),
    ALTER COLUMN review_comment_message TYPE TEXT USING NULLIF(review_comment_message, ''),
    ALTER COLUMN review_creation_date TYPE TIMESTAMP USING NULLIF(trim(review_creation_date), '')::timestamp,
    ALTER COLUMN review_answer_timestamp TYPE TIMESTAMP USING NULLIF(trim(review_answer_timestamp), '')::timestamp;

-- 8. ТОВАРЫ
ALTER TABLE analytics.olist_products_dataset
    ALTER COLUMN product_name_lenght TYPE SMALLINT USING NULLIF(trim(product_name_lenght), '')::smallint,
    ALTER COLUMN product_description_lenght TYPE SMALLINT USING NULLIF(trim(product_description_lenght), '')::smallint,
    ALTER COLUMN product_photos_qty TYPE SMALLINT USING NULLIF(trim(product_photos_qty), '')::smallint,
    ALTER COLUMN product_weight_g TYPE INTEGER  USING NULLIF(trim(product_weight_g), '')::integer,
    ALTER COLUMN product_length_cm TYPE SMALLINT USING NULLIF(trim(product_length_cm), '')::smallint,
    ALTER COLUMN product_height_cm TYPE SMALLINT USING NULLIF(trim(product_height_cm), '')::smallint,
    ALTER COLUMN product_width_cm TYPE SMALLINT USING NULLIF(trim(product_width_cm), '')::smallint;

-- 9. Категории
ALTER TABLE analytics.product_category_name_translation
    ALTER COLUMN product_category_name TYPE TEXT USING NULLIF(trim(product_category_name), ''),
    ALTER COLUMN product_category_name_english TYPE TEXT USING NULLIF(trim(product_category_name_english), '');


COMMIT;