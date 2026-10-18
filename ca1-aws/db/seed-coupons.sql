-- Ten valid coupons. The k6 workload only ever uses these codes
-- (an unknown code makes Product throw a 500 - that would measure a bug, not load).
USE servicedb;
INSERT IGNORE INTO coupon (code, discount, exp_date) VALUES
 ('SAVE5', 5, '31/12/2027'),  ('SAVE10', 10, '31/12/2027'), ('SAVE15', 15, '31/12/2027'),
 ('SAVE20', 20, '31/12/2027'), ('SAVE25', 25, '31/12/2027'), ('SAVE30', 30, '31/12/2027'),
 ('SAVE35', 35, '31/12/2027'), ('SAVE40', 40, '31/12/2027'), ('SAVE45', 45, '31/12/2027'),
 ('SAVE50', 50, '31/12/2027');
SELECT COUNT(*) AS coupons FROM coupon;
