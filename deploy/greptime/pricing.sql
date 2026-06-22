-- GreptimeDB model token pricing reference table
-- Loaded by init-pricing service. Prices are in RMB per 1M tokens.
--
-- Conversion note: USD prices were converted using 1 USD = 6.78 CNY
-- (approximate market rate as of 2026-06-21). Provider RMB rate cards,
-- if available, take precedence; these values are for dashboard cost
-- estimation only and should be updated when providers change pricing.
--
-- All rates below are the standard (cache-miss) API rates.

CREATE TABLE IF NOT EXISTS model_pricing (
    model STRING PRIMARY KEY,
    provider STRING,
    input_price_rmb_per_1m DOUBLE,
    output_price_rmb_per_1m DOUBLE,
    currency STRING,
    updated_at TIMESTAMP TIME INDEX
);

-- Clear and re-seed so the init script stays idempotent without
-- GreptimeDB's unsupported ON DUPLICATE KEY UPDATE clause.
DELETE FROM model_pricing;

INSERT INTO model_pricing (model, provider, input_price_rmb_per_1m, output_price_rmb_per_1m, currency, updated_at)
VALUES
    ('step-3.7-flash', 'StepFun', 1.36, 7.80, 'CNY', '2026-06-21 00:00:00'::TIMESTAMP),
    ('deepseek-v4-flash', 'DeepSeek', 0.95, 1.90, 'CNY', '2026-06-21 00:00:00'::TIMESTAMP),
    ('deepseek-v4-pro', 'DeepSeek', 2.95, 5.90, 'CNY', '2026-06-21 00:00:00'::TIMESTAMP),
    ('kimi-k2.6', 'Moonshot', 6.44, 27.12, 'CNY', '2026-06-21 00:00:00'::TIMESTAMP),
    ('kimi-k2.5', 'Moonshot', 4.07, 20.34, 'CNY', '2026-06-21 00:00:00'::TIMESTAMP);
