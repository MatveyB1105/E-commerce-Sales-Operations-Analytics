-- Проверка какие заказы еще полностью не оплачены
SELECT
    order_id,
    COUNT(*)                             AS n_payments,
    MAX(payment_sequential)              AS max_seq,
    MIN(payment_sequential)              AS min_seq,
    COUNT(DISTINCT payment_sequential)   AS n_distinct_seq
FROM analytics.olist_order_payments_dataset
GROUP BY order_id
HAVING COUNT(*) <> MAX(payment_sequential)          -- длина ≠ максимум
    OR MIN(payment_sequential) <> 1                 -- нумерация не с 1
    OR COUNT(DISTINCT payment_sequential) <> COUNT(*)  -- есть дубли seq
ORDER BY n_payments DESC;