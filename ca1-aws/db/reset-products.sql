-- Run BEFORE EVERY experiment run: GET /products returns the whole table,
-- so the table must start at the same size (200 rows) for runs to be comparable.
USE servicedb;
TRUNCATE TABLE product;
SET SESSION cte_max_recursion_depth = 1000;
INSERT INTO product (name, description, price, coupon_code)
WITH RECURSIVE seq (n) AS (SELECT 1 UNION ALL SELECT n + 1 FROM seq WHERE n < 200)
SELECT CONCAT('Product-', n), CONCAT('Seed product number ', n), 100.00 + n, 'SAVE10' FROM seq;
SELECT COUNT(*) AS products_after_reset FROM product;
