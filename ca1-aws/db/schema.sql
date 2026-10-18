-- CA1 schema. Matches the JPA entities (Product, Coupon) exactly.
-- Created ONCE, before any app instance starts, and the apps then run with ddl-auto=none
-- so that several Product instances booting together never race to migrate the schema.
CREATE DATABASE IF NOT EXISTS servicedb;
USE servicedb;

CREATE TABLE IF NOT EXISTS coupon (
  id          BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,
  code        VARCHAR(255) UNIQUE,
  discount    DECIMAL(38,2),
  exp_date    VARCHAR(255)
);

CREATE TABLE IF NOT EXISTS product (
  id          BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,
  name        VARCHAR(255),
  description VARCHAR(255),
  price       DECIMAL(38,2),
  coupon_code VARCHAR(255)
);
