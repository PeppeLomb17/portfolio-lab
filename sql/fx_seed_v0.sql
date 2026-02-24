BEGIN;

INSERT INTO portfolio.fx_rates_daily
    (base_ccy, quote_ccy, rate_date, rate, source)
VALUES
    ('USD', 'EUR', '2026-02-20'::date, 0.92::numeric, 'manual-demo')
ON CONFLICT (base_ccy, quote_ccy, rate_date)
DO UPDATE
SET rate = EXCLUDED.rate,
    source = EXCLUDED.source;

COMMIT;